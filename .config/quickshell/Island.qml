import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Services.Notifications
import Quickshell.Networking
import Quickshell.Hyprland

// Morphing Island — Phase 1 + 2 + 3 + 4 + 9 (base)
// Phase 1: pill shape, 3-zone hover expand, click-to-pin vs
// click-through-to-action.
// Phase 2: live clock (collapsed) + hero clock/date (expanded center zone).
// Phase 3: music-reactive EQ bars next to the collapsed clock.
// Phase 4: volume OSD (collapsed state) + media controls (expanded left
// zone, only while a player is actually playing).
// Phase 9 (base): SUPER+SPACE app launcher — the pill itself morphs into a
// search bar + results list, exactly like the volume OSD morphs it into a
// level meter. Not a separate window: same width/height Behavior springs
// the rest of the pill already uses.
// Right zone (expanded) is still just reserved space — status icons are a
// later phase.
PanelWindow {
    id: root

    color: "transparent"

    // Pin the island to the main monitor (Samsung Odyssey G5) only —
    // this is a single PanelWindow instance (not wrapped in a
    // Variants { model: Quickshell.screens } loop), so without an
    // explicit screen it would otherwise be left to whatever
    // default output Quickshell/Qt picks. Matched by output name
    // rather than hardcoding an index, since DP-2 is exactly what
    // `hyprctl monitors` currently reports for that display.
    screen: Quickshell.screens.find(s => s.name === "DP-2") ?? Quickshell.screens[0]

    // Hidden entirely whenever the focused workspace has a fullscreen
    // window (a game, a video player, etc.) — a floating pill sitting on
    // top of a fullscreen surface reads as broken, not "always on top".
    // Native Hyprland IPC state (Quickshell.Hyprland), no polling a CLI.
    readonly property bool fullscreenActive: Hyprland.focusedWorkspace?.hasFullscreen ?? false
    visible: !fullscreenActive

    // Reserve space for the resting (collapsed) pill so tiled windows don't
    // lay out underneath it. Only the collapsed footprint is reserved —
    // hover-expand/OSD/launcher are all allowed to overlay windows like any
    // floating popup, same as the video's islands do.
    // (Hyprland adds margins.top on top of this value itself, so don't
    // double-count it here — just cover from the pill's top offset down
    // to its collapsed bottom edge.)
    // Zeroed out while hidden for fullscreen so nothing keeps reserving
    // top-of-screen space against a window that's covering the whole
    // display anyway.
    exclusiveZone: fullscreenActive ? 0 : (shadowMargin + pill.collapsedHeight)
    WlrLayershell.namespace: "quickshell:morphingIsland"
    WlrLayershell.layer: WlrLayer.Overlay
    // Only grab exclusive keyboard focus while the launcher is actually
    // open — otherwise this window would swallow every keystroke on the
    // desktop at all times.
    WlrLayershell.keyboardFocus: (pill.launcherOpen || pill.ccOpen || pill.powerMenuOpen) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors.top: true
    margins.top: 2

    // Extra room around the pill so its drop shadow isn't clipped by the
    // Wayland surface. The mask below keeps input confined to the pill
    // itself, so this margin is purely visual and never eats clicks.
    readonly property real shadowMargin: 10

    // Strips low-value junk commonly present in YouTube-sourced MPRIS
    // metadata (tags like "(Official Video)" / "[Lyrics]" and the
    // "- Topic" auto-generated channel suffix) so the limited character
    // budget in the expanded left zone is spent on the actual title/artist.
    function cleanMediaText(text) {
        if (!text) return "";

        let cleaned = text;

        // Bracketed/parenthetical junk tags, case-insensitive.
        const junkPattern = /[\(\[]\s*(official\s+video|official\s+audio|official\s+music\s+video|lyrics|lyric\s+video|hd|4k|visualizer|audio|mv)\s*[\)\]]/gi;
        cleaned = cleaned.replace(junkPattern, "");

        // YouTube's auto-generated "<Artist> - Topic" channel name suffix.
        cleaned = cleaned.replace(/\s*-\s*Topic\s*$/i, "");

        // Trim leftover whitespace and dangling dashes.
        cleaned = cleaned.replace(/\s{2,}/g, " ");
        cleaned = cleaned.replace(/^[\s\-]+|[\s\-]+$/g, "");

        return cleaned;
    }

    // mm:ss formatter for the control center media card's progress bar —
    // MPRIS position/length are both plain seconds (doubles).
    function formatMediaTime(seconds) {
        if (!seconds || seconds < 0 || !isFinite(seconds)) return "0:00";
        const total = Math.floor(seconds);
        const m = Math.floor(total / 60);
        const s = total % 60;
        return m + ":" + (s < 10 ? "0" : "") + s;
    }

    // Manual rounded-rect path builder for the battery Canvas below.
    // QtQuick's Canvas 2D context doesn't implement the newer
    // `roundRect()` HTML5 addition, only the long-standing arcTo/lineTo
    // primitives, so the corners are built by hand instead. Only builds
    // the path — caller still does ctx.fill()/ctx.stroke() themselves.
    function roundedRectPath(ctx, x, y, w, h, r) {
        ctx.beginPath();
        ctx.moveTo(x + r, y);
        ctx.lineTo(x + w - r, y);
        ctx.arcTo(x + w, y, x + w, y + r, r);
        ctx.lineTo(x + w, y + h - r);
        ctx.arcTo(x + w, y + h, x + w - r, y + h, r);
        ctx.lineTo(x + r, y + h);
        ctx.arcTo(x, y + h, x, y + h - r, r);
        ctx.lineTo(x, y + r);
        ctx.arcTo(x, y, x + r, y, r);
        ctx.closePath();
    }

    // Network glyph — wifi signal meter normally, swapping to a wired
    // plug/port glyph whenever ethernet is the active connection. Defined
    // once here (inline component) and reused both by the expanded-state
    // status icon and by the control center's wifi tile, rather than
    // duplicating the same ~60 lines of Canvas paint code in two places.
    component NetworkGlyph: Canvas {
        id: networkGlyph
        width: 20
        height: 14

        readonly property bool ethernet: pill.usingEthernet
        readonly property bool wifiOn: Networking.wifiEnabled
        readonly property real strength: pill.wifiNetwork?.signalStrength ?? 0
        readonly property int level: strength <= 0 ? 0 : strength < 40 ? 1 : strength < 70 ? 2 : 3

        onEthernetChanged: requestPaint()
        onWifiOnChanged: requestPaint()
        onLevelChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Component.onCompleted: requestPaint()

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const activeColor = Colors.text;

            if (ethernet) {
                // RJ45 plug glyph: body + 3 top pins + a short cable stub
                // below.
                const cx = width / 2;
                const bodyW = 10, bodyH = 6;
                const bodyX = cx - bodyW / 2, bodyY = height / 2 - bodyH / 2;

                ctx.fillStyle = activeColor;
                root.roundedRectPath(ctx, bodyX, bodyY, bodyW, bodyH, 1.5);
                ctx.fill();

                const pinW = 1.4, pinH = 3, gap = 2.6;
                for (let i = -1; i <= 1; i++) {
                    ctx.fillRect(cx + i * gap - pinW / 2, bodyY - pinH, pinW, pinH);
                }

                ctx.strokeStyle = activeColor;
                ctx.lineWidth = 1.4;
                ctx.lineCap = "round";
                ctx.beginPath();
                ctx.moveTo(cx, bodyY + bodyH);
                ctx.lineTo(cx, bodyY + bodyH + 3);
                ctx.stroke();
                return;
            }

            // Wifi — the icon IS the signal meter: the dot at the base is
            // always drawn, and each of the three arcs above it lights up
            // as signal strength crosses its threshold. A disabled radio
            // dims the whole glyph and adds a strike-through instead of
            // inventing a fourth arc state.
            const dimColor = Colors.borderHover;
            const cx = width / 2;
            const cy = height - 2;

            ctx.beginPath();
            ctx.fillStyle = wifiOn ? activeColor : dimColor;
            ctx.arc(cx, cy, 1.3, 0, Math.PI * 2);
            ctx.fill();

            const radii = [3.5, 6.5, 9.5];
            for (let i = 0; i < radii.length; i++) {
                ctx.beginPath();
                ctx.strokeStyle = (wifiOn && level > i) ? activeColor : dimColor;
                ctx.lineWidth = 1.6;
                ctx.lineCap = "round";
                ctx.arc(cx, cy, radii[i], Math.PI * 1.22, Math.PI * 1.78);
                ctx.stroke();
            }

            if (!wifiOn) {
                ctx.beginPath();
                ctx.strokeStyle = Colors.critical;
                ctx.lineWidth = 1.4;
                ctx.lineCap = "round";
                ctx.moveTo(2, 2);
                ctx.lineTo(width - 2, height - 1);
                ctx.stroke();
            }
        }
    }

    // Audio glyph — speaker cone + up to two soundwave arcs scaling with
    // volume, swapping to a struck-through cone when muted. Same
    // hand-drawn-arcs visual language as NetworkGlyph above, reused by
    // the control center's audio tile.
    component AudioGlyph: Canvas {
        width: 20
        height: 14

        readonly property bool muted: pill.sink?.audio.muted ?? true
        readonly property real vol: pill.sink?.audio.volume ?? 0

        onMutedChanged: requestPaint()
        onVolChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Component.onCompleted: requestPaint()

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const activeColor = Colors.text;
            const dimColor = Colors.borderHover;
            const color = muted ? dimColor : activeColor;

            ctx.fillStyle = color;
            ctx.beginPath();
            ctx.moveTo(0, 5);
            ctx.lineTo(4, 5);
            ctx.lineTo(8, 1);
            ctx.lineTo(8, 13);
            ctx.lineTo(4, 9);
            ctx.lineTo(0, 9);
            ctx.closePath();
            ctx.fill();

            if (muted) {
                ctx.strokeStyle = Colors.critical;
                ctx.lineWidth = 1.4;
                ctx.lineCap = "round";
                ctx.beginPath();
                ctx.moveTo(10, 2);
                ctx.lineTo(18, 12);
                ctx.stroke();
            } else {
                const level = vol <= 0 ? 0 : vol < 0.5 ? 1 : 2;
                const radii = [3, 6];
                for (let i = 0; i < radii.length; i++) {
                    ctx.beginPath();
                    ctx.strokeStyle = level > i ? activeColor : dimColor;
                    ctx.lineWidth = 1.6;
                    ctx.lineCap = "round";
                    ctx.arc(8, 7, radii[i], -0.6, 0.6);
                    ctx.stroke();
                }
            }
        }
    }

    // Bluetooth glyph — the classic bowtie rune (spine + crossing
    // diagonals), same dimmed/strikethrough off-state treatment as
    // NetworkGlyph above rather than inventing a new visual language for
    // "radio disabled".
    component BluetoothGlyph: Canvas {
        id: bluetoothGlyph
        // Taller than wide, matching the real symbol's proportions (the
        // wide/short 20x14 box the other tile glyphs use flattened this
        // one into an unrecognizable triangle/flag shape).
        width: 16
        height: 22

        readonly property bool poweredOn: pill.bluetoothPowered

        onPoweredOnChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Component.onCompleted: requestPaint()

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const activeColor = Colors.text;
            const dimColor = Colors.borderHover;
            const color = poweredOn ? activeColor : dimColor;

            // The real Bluetooth glyph is a single zigzag: top point down
            // to the upper-right corner, back across through the center
            // to the lower-left corner, up to the bottom point, back up
            // through the center via the vertical spine, across to the
            // upper-right corner and down to the lower-left corner —
            // i.e. two triangular points meeting dead-center, one pair
            // angled top-center/upper-right/lower-left and the other
            // top-left/lower-right/bottom-center. This is the same
            // point sequence Feather Icons' "bluetooth" glyph traces
            // (a well-known, unambiguous reference for this shape),
            // just remapped onto our own canvas size below instead of
            // hand-guessed.
            const inset = 2;
            const spanX = width - inset * 2;
            const spanY = height - inset * 2;
            const px = (nx) => inset + nx * spanX;
            const py = (ny) => inset + ny * spanY;

            const p0 = [px(0), py(0.25)];   // upper-left
            const p1 = [px(1), py(0.75)];   // lower-right
            const p2 = [px(0.5), py(1)];    // bottom-center
            const p3 = [px(0.5), py(0)];    // top-center
            const p4 = [px(1), py(0.25)];   // upper-right
            const p5 = [px(0), py(0.75)];   // lower-left

            ctx.strokeStyle = color;
            ctx.lineWidth = 1.6;
            ctx.lineCap = "round";
            ctx.lineJoin = "round";

            ctx.beginPath();
            ctx.moveTo(p0[0], p0[1]);
            ctx.lineTo(p1[0], p1[1]);
            ctx.lineTo(p2[0], p2[1]);
            ctx.lineTo(p3[0], p3[1]);
            ctx.lineTo(p4[0], p4[1]);
            ctx.lineTo(p5[0], p5[1]);
            ctx.stroke();

            if (!poweredOn) {
                ctx.beginPath();
                ctx.strokeStyle = Colors.critical;
                ctx.lineWidth = 1.4;
                ctx.lineCap = "round";
                ctx.moveTo(2, 2);
                ctx.lineTo(width - 2, height - 2);
                ctx.stroke();
            }
        }
    }

    // Night light glyph — plain hand-drawn sun (circle + rays), no
    // signal-meter-style state beyond a color swap: warm amber while
    // active, muted gray while off. Spec calls this one a simple on/off
    // tile, so it doesn't need the fuller stateful treatment the network/
    // audio/battery glyphs get.
    component NightLightGlyph: Canvas {
        id: nightLightGlyph
        width: 20
        height: 20

        property bool active: false

        onActiveChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Component.onCompleted: requestPaint()

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const cx = width / 2, cy = height / 2;
            const color = active ? Colors.warning : Colors.textTertiary;

            ctx.fillStyle = color;
            ctx.beginPath();
            ctx.arc(cx, cy, 4.5, 0, Math.PI * 2);
            ctx.fill();

            ctx.strokeStyle = color;
            ctx.lineWidth = 1.4;
            ctx.lineCap = "round";
            for (let i = 0; i < 8; i++) {
                const ang = (Math.PI * 2 / 8) * i;
                ctx.beginPath();
                ctx.moveTo(cx + Math.cos(ang) * 7, cy + Math.sin(ang) * 7);
                ctx.lineTo(cx + Math.cos(ang) * 9.5, cy + Math.sin(ang) * 9.5);
                ctx.stroke();
            }
        }
    }

    // Peace (do-not-disturb) glyph — a plain bell when notifications are
    // on, a bell-slash (the universal "muted" mark, colored the same
    // active-accent blue every other tile uses for its on state) when
    // Peace mode is on. No signal-meter-style states beyond that, same
    // as NightLightGlyph above.
    component PeaceGlyph: Canvas {
        id: peaceGlyph
        width: 18
        height: 20

        property bool active: false

        onActiveChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Component.onCompleted: requestPaint()

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const color = active ? Colors.accent : Colors.textTertiary;
            const cx = width / 2;

            ctx.strokeStyle = color;
            ctx.fillStyle = color;
            ctx.lineWidth = 1.5;
            ctx.lineCap = "round";
            ctx.lineJoin = "round";

            // Bell: rounded dome + shoulders down to a base line, small
            // clapper below.
            ctx.beginPath();
            ctx.arc(cx, height * 0.42, 5.5, Math.PI, 0, false);
            ctx.lineTo(cx + 6, height * 0.72);
            ctx.lineTo(cx - 6, height * 0.72);
            ctx.closePath();
            ctx.stroke();

            ctx.beginPath();
            ctx.moveTo(cx - 8, height * 0.72);
            ctx.lineTo(cx + 8, height * 0.72);
            ctx.stroke();

            ctx.beginPath();
            ctx.arc(cx, height * 0.72 + 3, 1.8, 0, Math.PI * 2);
            ctx.fill();

            if (active) {
                ctx.beginPath();
                ctx.strokeStyle = color;
                ctx.lineWidth = 1.8;
                ctx.moveTo(2, height - 2);
                ctx.lineTo(width - 2, 2);
                ctx.stroke();
            }
        }
    }

    // Power menu (Ctrl+Alt+Delete) tile icons — same hand-drawn-Canvas
    // language as the glyphs above, defined once here and reused by the
    // power menu's five tiles below. None of these need stateful redraws
    // (no signal-strength/volume-level style variation — each is just a
    // fixed glyph), so they paint once on completion and never repaint.
    component LockGlyph: Canvas {
        width: 18
        height: 20

        Component.onCompleted: requestPaint()

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const color = Colors.text;
            const cx = width / 2;

            // Shackle: a dome arc with two short legs dropping into the
            // body, same "arc + lineTo shoulders" recipe as PeaceGlyph's
            // bell dome above.
            ctx.strokeStyle = color;
            ctx.lineWidth = 1.8;
            ctx.lineCap = "round";
            ctx.beginPath();
            ctx.arc(cx, 7, 5, Math.PI, 0, false);
            ctx.lineTo(cx + 5, 10);
            ctx.moveTo(cx - 5, 7);
            ctx.lineTo(cx - 5, 10);
            ctx.stroke();

            // Body.
            ctx.fillStyle = color;
            root.roundedRectPath(ctx, cx - 7, 9, 14, 10, 2.5);
            ctx.fill();

            // Keyhole.
            ctx.fillStyle = Colors.background;
            ctx.beginPath();
            ctx.arc(cx, 13, 1.6, 0, Math.PI * 2);
            ctx.fill();
            ctx.fillRect(cx - 0.8, 13, 1.6, 3);
        }
    }

    // Suspend glyph — crescent moon, drawn as a filled circle with a
    // second offset circle cut out of it via destination-out compositing
    // rather than hand-plotting a crescent path.
    component SuspendGlyph: Canvas {
        width: 18
        height: 18

        Component.onCompleted: requestPaint()

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const color = Colors.text;

            ctx.fillStyle = color;
            ctx.beginPath();
            ctx.arc(9, 9, 7, 0, Math.PI * 2);
            ctx.fill();

            ctx.globalCompositeOperation = "destination-out";
            ctx.beginPath();
            ctx.arc(12.5, 6.5, 6.2, 0, Math.PI * 2);
            ctx.fill();
            ctx.globalCompositeOperation = "source-over";
        }
    }

    // Log out glyph — an open door frame with an arrow exiting through it.
    component LogoutGlyph: Canvas {
        width: 20
        height: 18

        Component.onCompleted: requestPaint()

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const color = Colors.text;

            ctx.strokeStyle = color;
            ctx.lineWidth = 1.8;
            ctx.lineCap = "round";
            ctx.lineJoin = "round";

            // Door frame.
            ctx.beginPath();
            ctx.moveTo(8, 1);
            ctx.lineTo(2, 1);
            ctx.lineTo(2, 17);
            ctx.lineTo(8, 17);
            ctx.stroke();

            // Arrow shaft + head, pointing out through the frame.
            ctx.beginPath();
            ctx.moveTo(6, 9);
            ctx.lineTo(18, 9);
            ctx.stroke();

            ctx.beginPath();
            ctx.moveTo(13, 4);
            ctx.lineTo(18, 9);
            ctx.lineTo(13, 14);
            ctx.stroke();
        }
    }

    // Reboot glyph — a near-complete circular arc with an arrowhead at
    // its open end, the standard "refresh" shape.
    component RebootGlyph: Canvas {
        width: 18
        height: 18

        Component.onCompleted: requestPaint()

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const color = Colors.text;
            const cx = 9, cy = 9, r = 6.5;
            const startAngle = -0.4;

            ctx.strokeStyle = color;
            ctx.lineWidth = 1.8;
            ctx.lineCap = "round";
            ctx.beginPath();
            ctx.arc(cx, cy, r, startAngle, Math.PI * 1.55, false);
            ctx.stroke();

            const ex = cx + Math.cos(startAngle) * r;
            const ey = cy + Math.sin(startAngle) * r;
            ctx.beginPath();
            ctx.moveTo(ex - 4, ey - 2.5);
            ctx.lineTo(ex + 1, ey);
            ctx.lineTo(ex - 1.5, ey + 4);
            ctx.stroke();
        }
    }

    // Power glyph — the standard power symbol: a ring with a gap at the
    // top, and a stem passing through the gap into the ring's center.
    component PowerGlyph: Canvas {
        width: 18
        height: 18

        Component.onCompleted: requestPaint()

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const color = Colors.text;
            const cx = 9, cy = 10, r = 6;
            const gapHalf = 0.55;

            ctx.strokeStyle = color;
            ctx.lineWidth = 1.8;
            ctx.lineCap = "round";
            ctx.beginPath();
            ctx.arc(cx, cy, r, -Math.PI / 2 + gapHalf, -Math.PI / 2 - gapHalf + Math.PI * 2, false);
            ctx.stroke();

            ctx.beginPath();
            ctx.moveTo(cx, cy - r - 4);
            ctx.lineTo(cx, cy - 1);
            ctx.stroke();
        }
    }

    // IMPORTANT: the window's own geometry is fixed at the largest
    // footprint the pill will ever need (expanded hover state OR the
    // launcher's search+results card, whichever is bigger) and never
    // animates. Only the pill *inside* it grows/shrinks. Animating
    // implicitWidth/Height directly would resize the actual
    // wlr-layer-shell surface every spring frame, which is a negotiated,
    // async operation — under real compositor timing that races with the
    // hover mask and can make the island collapse out from under the
    // cursor mid-hover. Keeping the surface static and only moving the
    // mask (a cheap client-side input-region update) avoids that entirely.
    implicitWidth: Math.max(pill.expandedWidth, pill.launcherWidth, pill.ccWidth, pill.pmWidth) + shadowMargin * 2
    implicitHeight: Math.max(pill.expandedHeight, pill.launcherMaxHeight, pill.ccMaxHeight, pill.pmHeight) + shadowMargin * 2

    mask: Region {
        item: pill
    }

    // `quickshell ipc call launcher toggle|open|close` — bound to
    // SUPER+SPACE in hyprland.lua. IPC (not a Quickshell.Hyprland
    // GlobalShortcut) so this doesn't depend on the xdg-desktop-portal
    // global-shortcuts portal being present/granted — a plain Hyprland
    // `bind` + `quickshell ipc call` always works.
    IpcHandler {
        target: "launcher"

        function toggle(): void {
            if (pill.launcherOpen) pill.closeLauncher(); else pill.openLauncher();
        }
        function open(): void {
            pill.openLauncher();
        }
        function close(): void {
            pill.closeLauncher();
        }
    }

    // `quickshell ipc call controlcenter toggle|open|close` — bound to
    // Alt+A in hyprland.lua. Same IPC pattern as the launcher above.
    IpcHandler {
        target: "controlcenter"

        function toggle(): void {
            if (pill.ccOpen) pill.closeControlCenter(); else pill.openControlCenter();
        }
        function open(): void {
            pill.openControlCenter();
        }
        function close(): void {
            pill.closeControlCenter();
        }
    }

    // `quickshell ipc call powermenu toggle|open|close` — bound to
    // Ctrl+Alt+Delete in hyprland.lua. Same IPC pattern as the launcher/
    // control center above.
    IpcHandler {
        target: "powermenu"

        function toggle(): void {
            if (pill.powerMenuOpen) pill.closePowerMenu(); else pill.openPowerMenu();
        }
        function open(): void {
            pill.openPowerMenu();
        }
        function close(): void {
            pill.closePowerMenu();
        }
    }

    // Single tick source shared by every clock in the island (collapsed
    // time + expanded hero clock/date), so they never drift apart.
    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: clock.now = new Date()
    }

    QtObject {
        id: clock
        property var now: new Date()
    }

    // Reset back to resting/collapsed the moment fullscreen hides the
    // island, so it doesn't silently pop back in already pinned/expanded
    // (or mid-launcher) the instant the fullscreen window closes.
    onFullscreenActiveChanged: {
        if (fullscreenActive) {
            pill.pinned = false;
            pill.hovered = false;
            pill.closeLauncher();
            pill.closeControlCenter();
            pill.closePowerMenu();
            pill.closeActiveNotif(false);
        }
    }

    Item {
        id: surface
        anchors.fill: parent

        Item {
            id: pill
            // Anchored to the top (not centered in the static surface) so
            // its top edge stays fixed at all times and it only grows
            // downward on expand — otherwise, since the surface is sized
            // for the expanded footprint, a centered pill would float in
            // the middle of that invisible box while collapsed: well below
            // the reserved-space strip, overlapping windows instead of
            // clearing them.
            anchors.top: parent.top
            anchors.topMargin: root.shadowMargin
            anchors.horizontalCenter: parent.horizontalCenter

            property bool pinned: false
            property bool hovered: false
            property bool expanded: pinned || hovered

            // True the moment any MPRIS player (Spotify, browser media,
            // etc.) is actively playing. Reactively follows Quickshell's
            // native MPRIS service — no playerctl/shelling out.
            property bool musicPlaying: Mpris.players.values.some(p => p.isPlaying)
            // The player driving musicPlaying — used by the media controls
            // for track info and transport actions.
            property var activePlayer: Mpris.players.values.find(p => p.isPlaying) ?? null

            // --- Control center media card visibility — deliberately a
            // separate gate from musicPlaying/activePlayer above (those
            // keep driving the pill's own collapsed-state EQ bars and
            // expanded-state media zone exactly as before). The card
            // itself should survive a pause instead of vanishing the
            // instant playback stops, so it needs its own "sticky" player
            // reference plus a 45s grace timer rather than a direct
            // musicPlaying binding. ---
            //
            // Sticky reference to whichever player the card is showing —
            // a self-referential binding (falls back to its own current
            // value whenever activePlayer goes null) rather than an
            // onActivePlayerChanged assignment, specifically so it also
            // picks up the right value on the very first evaluation at
            // startup: QML property-change handlers don't fire for a
            // property's initial binding, only real subsequent changes,
            // so an imperative-only version of this would stay stuck at
            // null forever if a player happened to already be playing
            // when quickshell launched. Left untouched across a pause so
            // the card keeps showing that same track — including its
            // now-paused state, which the play/pause button already
            // reflects via isPlaying — instead of going blank.
            property var ccMediaPlayer: activePlayer ?? ccMediaPlayer
            // Flips true once ccMediaHideTimer's 45s grace period has
            // elapsed with nothing playing. Reset (and the timer
            // stopped) the moment anything starts playing again.
            property bool ccMediaGraceExpired: false

            onActivePlayerChanged: {
                if (activePlayer) {
                    ccMediaGraceExpired = false;
                    ccMediaHideTimer.stop();
                } else {
                    ccMediaHideTimer.restart();
                }
            }

            Timer {
                id: ccMediaHideTimer
                interval: 45000
                repeat: false
                onTriggered: pill.ccMediaGraceExpired = true
            }

            // Visible whenever there's a track to show AND either
            // something's actually playing, the control center is open
            // (never auto-hide while the user's looking at it, no matter
            // how long it's been paused), or the 45s grace period since
            // the last pause hasn't run out yet.
            readonly property bool ccMediaVisible: ccMediaPlayer !== null
                && (musicPlaying || ccOpen || !ccMediaGraceExpired)

            // MPRIS servers generally don't emit PropertiesChanged for
            // Position while a track is playing (the spec expects clients
            // to poll) — so the control center's media card progress bar
            // re-reads ccMediaPlayer.position on a short timer rather
            // than binding to it directly, which would just sit frozen
            // at whatever value it last had on track/seek change. Only
            // runs while the card is actually visible and the sticky
            // player is actively playing, so it's not ticking in the
            // background the rest of the time (and stays frozen, as
            // intended, while paused).
            property real mediaPosition: pill.ccMediaPlayer?.position ?? 0
            Timer {
                interval: 500
                repeat: true
                running: pill.ccOpen && pill.ccMediaVisible && (pill.ccMediaPlayer?.isPlaying ?? false)
                onTriggered: pill.mediaPosition = pill.ccMediaPlayer?.position ?? 0
            }

            // Native Pipewire default sink — no wpctl shelling out. Volume
            // OSD state: shows while true, melts back after a quiet period.
            property var sink: Pipewire.defaultAudioSink
            property bool osdVisible: false

            PwObjectTracker {
                objects: pill.sink ? [pill.sink] : []
            }

            // Native NetworkManager-backed wifi state (Quickshell.Networking)
            // — no `nmcli`/`iwctl` shelling out. First wifi-type device
            // found, and whichever of its networks is currently connected
            // (both null when there's no wifi hardware or no active
            // connection — the right-zone icon degrades gracefully rather
            // than assuming either always exists).
            property var wifiDevice: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
            property var wifiNetwork: pill.wifiDevice
                ? (pill.wifiDevice.networks.values.find(n => n.connected) ?? null)
                : null

            // Same idea for wired — when an ethernet device actually has
            // an active connection, that's the icon the right zone shows
            // instead of the wifi meter (a machine plugged into ethernet
            // has nothing meaningful for a wifi signal-strength glyph to
            // report anyway).
            property var wiredDevice: Networking.devices.values.find(d => d.type === DeviceType.Wired) ?? null
            readonly property bool usingEthernet: pill.wiredDevice?.connected ?? false

            // Native UPower battery state (Quickshell.Services.UPower) — no
            // `upower`/`acpi` shelling out. `isPresent` is false on
            // desktops with no battery at all, which the right-zone icon
            // uses to hide itself rather than showing a fake 0%/100%.
            readonly property var battery: UPower.displayDevice
            readonly property bool batteryPresent: pill.battery?.isPresent ?? false
            readonly property real batteryPct: pill.battery?.percentage ?? 0
            readonly property bool batteryCharging: pill.battery?.state === UPowerDeviceState.Charging

            // All real output devices (native Pipewire, no wpctl) — the
            // control center's audio sub-view lists these for switching,
            // each with its own volume slider. Excludes streams (per-app
            // sink-inputs), only actual sinks.
            readonly property var audioSinks: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio)

            PwObjectTracker {
                objects: pill.audioSinks
            }

            // Night light — no clean IPC that stays reliable across
            // hyprsunset versions (its own author's dotfiles hit the same
            // wall, see plan/spec.md's note on this), so state is tracked
            // the same pragmatic way: whether the process is alive.
            property bool nightLightActive: false

            function refreshNightLight() {
                nightLightCheckProc.running = true;
            }

            Process {
                id: nightLightCheckProc
                command: ["pidof", "hyprsunset"]
                onExited: (exitCode) => pill.nightLightActive = (exitCode === 0)
            }

            function toggleNightLight() {
                if (pill.nightLightActive) {
                    Quickshell.execDetached(["pkill", "hyprsunset"]);
                    pill.nightLightActive = false;
                } else {
                    Quickshell.execDetached(["bash", "-c", "hyprsunset --temperature 4000 & disown"]);
                    pill.nightLightActive = true;
                }
            }

            // Screen brightness — same pragmatic shelling-out as night
            // light/bluetooth above: no native Quickshell service for
            // this, so `brightnessctl` is the source of truth. Tracked as
            // a current/max pair (rather than a single 0-1 fraction)
            // because that's what the tool itself reports — computing
            // the displayed percentage from them, instead of trying to
            // maintain a fraction directly, is what keeps this honest
            // after an external change (a hardware brightness key, say)
            // the next time the control center opens and re-reads it.
            property real brightnessCurrent: 0
            property real brightnessMax: 100
            readonly property real brightnessPct: brightnessMax > 0 ? brightnessCurrent / brightnessMax : 0

            function refreshBrightness() {
                brightnessMaxProc.buffer = "";
                brightnessMaxProc.running = true;
            }

            Process {
                id: brightnessMaxProc
                property string buffer: ""
                command: ["brightnessctl", "m"]
                stdout: SplitParser {
                    onRead: (line) => brightnessMaxProc.buffer += line
                }
                onExited: (exitCode) => {
                    const max = parseInt(brightnessMaxProc.buffer.trim());
                    if (exitCode === 0 && !isNaN(max)) pill.brightnessMax = max;
                    // Chained rather than run in parallel — the percentage
                    // this feeds is only meaningful once both numbers are
                    // in, so there's no point racing two Processes for it.
                    brightnessCurrentProc.buffer = "";
                    brightnessCurrentProc.running = true;
                }
            }

            Process {
                id: brightnessCurrentProc
                property string buffer: ""
                command: ["brightnessctl", "g"]
                stdout: SplitParser {
                    onRead: (line) => brightnessCurrentProc.buffer += line
                }
                onExited: (exitCode) => {
                    const cur = parseInt(brightnessCurrentProc.buffer.trim());
                    if (exitCode === 0 && !isNaN(cur)) pill.brightnessCurrent = cur;
                }
            }

            // Optimistic local update (instant slider feedback, same as
            // the audio sub-view's per-device volume sliders) + shelling
            // out to actually change the backlight. Takes 0-1 like the
            // slider works in, converts to the percent brightnessctl's
            // `set` wants.
            function setBrightness(pct) {
                const clamped = Math.max(0, Math.min(1, pct));
                pill.brightnessCurrent = clamped * pill.brightnessMax;
                brightnessSetProc.command = ["brightnessctl", "s", Math.round(clamped * 100) + "%"];
                brightnessSetProc.running = true;
            }

            Process {
                id: brightnessSetProc
            }

            // Bluetooth — no native Quickshell service for this (unlike
            // wifi/audio/battery/mpris above), so it shells out to
            // `bluetoothctl` directly, built fresh against its actual
            // text output rather than adapted from any old waybar
            // script. Three pieces: power state, the paired-device list,
            // and per-device connected status (each paired device needs
            // its own `bluetoothctl info <mac>` call — bluetoothctl has
            // no single command that lists paired devices with their
            // connection state together).
            property bool bluetoothPowered: false
            property var bluetoothDevices: []  // [{mac, name, connected}]
            property var btPairedRaw: []       // [{mac, name}] — most recent `devices Paired` parse
            property int btInfoQueueIndex: 0

            function refreshBluetoothPower() {
                btPowerCheckProc.buffer = "";
                btPowerCheckProc.running = true;
            }

            Process {
                id: btPowerCheckProc
                property string buffer: ""
                command: ["bluetoothctl", "show"]
                stdout: SplitParser {
                    onRead: (line) => btPowerCheckProc.buffer += line + "\n"
                }
                onExited: (exitCode) => {
                    pill.bluetoothPowered = exitCode === 0 && btPowerCheckProc.buffer.includes("Powered: yes");
                }
            }

            function toggleBluetoothPower() {
                const turningOn = !pill.bluetoothPowered;
                // Optimistic — bluetoothctl's own power command is quick,
                // but the confirming refresh below is what actually
                // settles the icon to ground truth either way.
                pill.bluetoothPowered = turningOn;
                btPowerToggleProc.command = ["bluetoothctl", "power", turningOn ? "on" : "off"];
                btPowerToggleProc.running = true;
            }

            Process {
                id: btPowerToggleProc
                onExited: pill.refreshBluetoothPower()
            }

            function refreshBluetoothDevices() {
                btPairedListProc.buffer = [];
                btPairedListProc.running = true;
            }

            Process {
                id: btPairedListProc
                property var buffer: []
                command: ["bluetoothctl", "devices", "Paired"]
                stdout: SplitParser {
                    onRead: (line) => btPairedListProc.buffer.push(line)
                }
                onExited: (exitCode) => {
                    if (exitCode !== 0) {
                        pill.bluetoothDevices = [];
                        return;
                    }
                    // "Device <MAC> <Name>" per line.
                    pill.btPairedRaw = btPairedListProc.buffer
                        .map(line => {
                            const m = line.match(/^Device\s+([0-9A-Fa-f:]{17})\s+(.*)$/);
                            return m ? { mac: m[1], name: m[2] } : null;
                        })
                        .filter(d => d !== null);
                    // Seeded as disconnected until each device's own
                    // `info` call (below) confirms otherwise, so the list
                    // renders immediately instead of staying empty while
                    // the per-device queue drains.
                    pill.bluetoothDevices = pill.btPairedRaw.map(d => ({ mac: d.mac, name: d.name, connected: false }));
                    pill.btInfoQueueIndex = 0;
                    pill.fetchNextBtInfo();
                }
            }

            function fetchNextBtInfo() {
                if (pill.btInfoQueueIndex >= pill.btPairedRaw.length) return;
                btInfoProc.buffer = "";
                btInfoProc.command = ["bluetoothctl", "info", pill.btPairedRaw[pill.btInfoQueueIndex].mac];
                btInfoProc.running = true;
            }

            Process {
                id: btInfoProc
                property string buffer: ""
                stdout: SplitParser {
                    onRead: (line) => btInfoProc.buffer += line + "\n"
                }
                onExited: (exitCode) => {
                    const connected = exitCode === 0 && btInfoProc.buffer.includes("Connected: yes");
                    const idx = pill.btInfoQueueIndex;
                    if (idx < pill.bluetoothDevices.length) {
                        const updated = pill.bluetoothDevices.slice();
                        updated[idx] = { mac: updated[idx].mac, name: updated[idx].name, connected: connected };
                        pill.bluetoothDevices = updated;
                    }
                    pill.btInfoQueueIndex++;
                    pill.fetchNextBtInfo();
                }
            }

            function toggleBluetoothDeviceConnection(device) {
                if (!device) return;
                btConnectProc.command = ["bluetoothctl", device.connected ? "disconnect" : "connect", device.mac];
                btConnectProc.running = true;
            }

            Process {
                id: btConnectProc
                onExited: pill.refreshBluetoothDevices()
            }

            // Only polls while the bluetooth sub-view is actually open
            // (started/stopped from onCcViewChanged below) — a few
            // seconds is fresh enough for a manual settings panel and
            // avoids shelling out to bluetoothctl in the background the
            // rest of the time.
            Timer {
                id: bluetoothPollTimer
                interval: 4000
                repeat: true
                onTriggered: {
                    pill.refreshBluetoothPower();
                    pill.refreshBluetoothDevices();
                }
            }

            Timer {
                id: osdMeltTimer
                interval: 1500
                onTriggered: pill.osdVisible = false
            }

            // --- Notifications (org.freedesktop.Notifications, native
            // Quickshell.Services.Notifications — no dunst/mako shelling
            // out) + Peace (do-not-disturb) mode. ---
            //
            // An incoming notification morphs the pill the same way the
            // volume/brightness OSD does above: a compact card fades in
            // and melts back on its own. Unlike the OSD's plain melt
            // timer, though, this one needs to be pausable — hovering
            // the card should stop the countdown, not just delay it —
            // so it's driven by an elapsed-time counter ticked forward
            // by a small interval timer (see notifTickTimer below)
            // rather than a single-shot Timer restarted from zero.
            property bool peaceMode: false
            property var notifHistory: []  // [{id, appName, appIcon, summary, body, critical, time}], newest first
            property var activeNotif: null // display snapshot of the current popup, or null
            property var activeNotifObj: null // live Notification behind activeNotif, only while a popup is up
            property bool notifVisible: false
            property bool notifHovered: false
            property real notifElapsed: 0
            property real notifTimeoutMs: 4000
            property int notifSeq: 0

            readonly property real notifWidth: 340
            readonly property real notifHeight: 68

            // Deterministic per-app hue, same hashed-char-code trick the
            // launcher's letter-avatar fallback uses (see resultRow
            // below), so a given app's avatar color stays put between
            // notifications instead of flickering.
            function notifAvatarColor(name) {
                const hue = Array.from(name || "?")
                    .reduce((sum, ch) => sum + ch.charCodeAt(0), 0) % 360;
                return Qt.hsla(hue / 360, 0.45, 0.35, 1);
            }

            // Closes whatever notification is currently popped up.
            // `userDismissed` picks which close reason the sender sees —
            // an explicit click reports Dismissed, the countdown running
            // out reports Expired — same distinction
            // NotificationCloseReason draws natively, so senders that
            // care (progress notifications, some chat apps) see the real
            // reason rather than always being told the user dismissed it.
            function closeActiveNotif(userDismissed) {
                if (pill.activeNotifObj) {
                    if (userDismissed) pill.activeNotifObj.dismiss();
                    else pill.activeNotifObj.expire();
                    // Deliberately NOT untracked here anymore — this only
                    // closes the POPUP. The underlying Notification stays
                    // tracked for as long as its entry lives in
                    // notifHistory (see onNotification/
                    // removeNotifHistoryEntry/clearNotifHistory below),
                    // so a history row can still invoke its default
                    // action long after the popup itself melted away.
                    pill.activeNotifObj = null;
                }
                pill.notifVisible = false;
                pill.activeNotif = null;
                // hoverZone.overPill is always live (see hoverTracker's
                // comment), so this reads the mouse's real, current
                // position rather than whatever pill.hovered last had
                // written to it — otherwise a click-dismiss (cursor
                // genuinely on the pill) or a timeout that happens to
                // land right as the cursor arrives would leave
                // pill.hovered stuck at a stale reading from before the
                // notification closed, spuriously snapping the pill into
                // (or out of) the hover-expand view right after dismiss.
                pill.hovered = hoverZone.overPill;
            }

            function clearNotifHistory() {
                pill.notifHistory.forEach((entry) => {
                    if (entry.notifObj) entry.notifObj.tracked = false;
                });
                pill.notifHistory = [];
            }

            // Removes a single history entry (the row's own "X" button),
            // releasing that notification's tracked hold same as
            // clearNotifHistory does for all of them.
            function removeNotifHistoryEntry(id) {
                const idx = pill.notifHistory.findIndex((entry) => entry.id === id);
                if (idx === -1) return;
                if (pill.notifHistory[idx].notifObj) pill.notifHistory[idx].notifObj.tracked = false;
                const updated = pill.notifHistory.slice();
                updated.splice(idx, 1);
                pill.notifHistory = updated;
            }

            // Click-to-open a history entry: freedesktop's convention is
            // that clicking a notification invokes its "default" action
            // (a browser's "focus this tab", a chat app's "open this
            // conversation", etc.) — not every notification has one (a
            // plain notify-send test, for instance), so this is a no-op
            // when there isn't a matching action rather than an error.
            // Manual index loop rather than .find/.filter — `actions` is
            // a QML list<T>, not guaranteed to support JS Array methods.
            function activateNotifHistoryEntry(entry) {
                if (!entry.notifObj) return;
                const actions = entry.notifObj.actions;
                for (let i = 0; i < actions.length; i++) {
                    if (actions[i].identifier === "default") {
                        actions[i].invoke();
                        return;
                    }
                }
            }

            Timer {
                id: notifTickTimer
                interval: 100
                repeat: true
                running: pill.notifVisible && !pill.notifHovered
                onTriggered: {
                    pill.notifElapsed += interval;
                    if (pill.notifElapsed >= pill.notifTimeoutMs) {
                        pill.closeActiveNotif(false);
                    }
                }
            }

            NotificationServer {
                id: notifServer
                keepOnReload: true
                bodySupported: true
                bodyMarkupSupported: false
                imageSupported: true
                // Advertised so senders that check capabilities before
                // attaching a "default" click action (browsers, chat
                // apps) actually populate one — needed for the history
                // list's click-to-open behavior below to have anything
                // to invoke.
                actionsSupported: true
                persistenceSupported: false

                onNotification: (notification) => {
                    // Tracked for as long as its history entry exists —
                    // NOT untracked on popup close/peace-suppress/replace
                    // like earlier versions of this did, since the
                    // history row needs the live object later to invoke
                    // its default action on click. Only
                    // removeNotifHistoryEntry/clearNotifHistory (actually
                    // dropping the entry) untrack it now.
                    notification.tracked = true;

                    pill.notifSeq++;
                    const critical = notification.urgency === NotificationUrgency.Critical;
                    const entry = {
                        id: pill.notifSeq,
                        appName: notification.appName || "Notification",
                        appIcon: notification.appIcon || notification.image || "",
                        summary: notification.summary || "",
                        body: notification.body || "",
                        critical: critical,
                        time: Date.now(),
                        notifObj: notification,
                    };
                    // History always gets it, Peace mode or not — only
                    // the popup morph below is conditional.
                    pill.notifHistory = [entry, ...pill.notifHistory];

                    if (pill.peaceMode) {
                        return;
                    }

                    // An incoming notification always interrupts, even if
                    // the cursor happens to already be resting on the
                    // pill (hoverZone's own HoverHandler freezes its
                    // hovered/position state the instant notifVisible
                    // disables it, so without this a stale "already
                    // hovering" reading from before the notification
                    // arrived would otherwise leave pill.expanded stuck
                    // true and hide the popup behind the hover-expand
                    // view for its entire lifetime).
                    pill.hovered = false;
                    pill.activeNotifObj = notification;
                    pill.activeNotif = entry;
                    pill.notifElapsed = 0;
                    // Respect a sender-specified timeout when it gave one;
                    // otherwise critical notifications linger noticeably
                    // longer than normal ones.
                    pill.notifTimeoutMs = notification.expireTimeout > 0
                        ? notification.expireTimeout
                        : (critical ? 8000 : 4000);
                    pill.notifVisible = true;
                }
            }

            Connections {
                target: pill.sink?.audio ?? null
                function onVolumeChanged() {
                    pill.osdVisible = true;
                    osdMeltTimer.restart();
                }
                function onMutedChanged() {
                    pill.osdVisible = true;
                    osdMeltTimer.restart();
                }
            }

            readonly property real collapsedWidth: 130
            readonly property real collapsedHeight: 34
            readonly property real osdWidth: 220
            readonly property real expandedWidth: 640
            readonly property real expandedHeight: 68

            // --- App launcher (SUPER+SPACE) ---
            property bool launcherOpen: false
            readonly property real launcherWidth: 420
            readonly property real launcherHeaderHeight: 56
            readonly property real launcherRowHeight: 44
            readonly property real launcherListPadding: 8
            readonly property int launcherMaxResults: 8
            // Upper bound used only to size the (static) window footprint —
            // the live height below can be anything up to this.
            readonly property real launcherMaxHeight: launcherHeaderHeight
                + launcherMaxResults * launcherRowHeight + launcherListPadding * 2

            // --- Control center (Alt+A) ---
            property bool ccOpen: false
            // "tiles" (the toggle grid) | "wifi" | "audio" | "bluetooth" —
            // which page of the sliding row (see controlCenter below) is
            // showing.
            property string ccView: "tiles"
            readonly property int ccViewIndex: ccView === "wifi" ? 1 : ccView === "audio" ? 2 : ccView === "bluetooth" ? 3 : 0

            // WifiDevice.scannerEnabled has to be turned on for its
            // `networks` list to actually populate/refresh — Quickshell's
            // equivalent of `nmcli device wifi rescan`. Only runs while
            // the wifi sub-view is actually visible, not continuously.
            // Bluetooth has no equivalent native service to toggle, so its
            // freshness instead comes from bluetoothPollTimer, started/
            // stopped the same way.
            onCcViewChanged: {
                if (wifiDevice) wifiDevice.scannerEnabled = (ccView === "wifi");
                if (ccView === "bluetooth") {
                    refreshBluetoothPower();
                    refreshBluetoothDevices();
                    bluetoothPollTimer.start();
                } else {
                    bluetoothPollTimer.stop();
                }
            }

            readonly property real ccPadding: 14
            readonly property real ccTileSize: 78
            readonly property real ccTileSpacing: 12
            readonly property int ccTileCount: 5  // Wifi, Audio, Night, Bluetooth, Peace
            // Derived from the actual tile row math (padding + N tiles +
            // (N-1) gaps) rather than a hand-picked number, so it can't
            // silently drift out of sync with the tiles Row below if a
            // tile is ever added/removed/resized again — this is exactly
            // the bug the 4th (bluetooth) tile just ran into: ccWidth was
            // still the 3-tile number, so the row quietly overflowed it.
            readonly property real ccWidth: ccPadding * 2
                + ccTileCount * ccTileSize + (ccTileCount - 1) * ccTileSpacing

            readonly property real ccSubHeaderHeight: 44
            readonly property real ccWifiRowHeight: 40
            readonly property int ccWifiMaxRows: 5
            readonly property real ccAudioRowHeight: 62
            readonly property int ccAudioMaxRows: 4
            readonly property real ccBluetoothRowHeight: 40
            readonly property int ccBluetoothMaxRows: 5

            // --- Home view (tiles page) — Android-quick-settings style:
            // the tile grid, a volume slider, a brightness slider, and
            // notification history all visible together, no sub-page
            // navigation needed for any of them. Wifi/audio/bluetooth
            // device lists are the only things still behind their own
            // slide-in page (opened by tapping a tile), since those need
            // real navigation (a "back" affordance) that a handful of
            // always-visible rows don't.
            readonly property real ccSliderRowHeight: 50  // label/value row + thick bar + thumb clearance
            // Media card — only ever occupies space while a player is
            // actually playing (see ccHomeHeight below); title/artist +
            // transport row + progress bar + output device label, all
            // fitted inside this fixed footprint.
            readonly property real ccMediaCardHeight: 208
            readonly property real ccHistoryRowHeight: 52
            readonly property real ccHistoryRowSpacing: 4  // gap between history rows, so they read as separate cards
            readonly property int ccHistoryMaxRows: 4
            readonly property real ccHistoryLabelHeight: 22
            // Extra reserved strip below the list for the "Clear all"
            // button — same fixed-footer idea as ccSubHeaderHeight is for
            // the sub-pages' headers, just at the bottom instead of the
            // top.
            readonly property real ccHistoryFooterHeight: 36

            // Small uppercase section labels (matching "Notifications"
            // above the history list) and a hairline divider between the
            // three home-view groups, purely so tiles/sliders/history read
            // as distinct sections instead of one continuous block.
            readonly property real ccSectionLabelHeight: 14
            readonly property real ccSectionLabelGap: 8
            readonly property real ccDividerHeight: 1

            // Number of history rows actually laid out right now, shared
            // by every height calc below so the row-height and row-spacing
            // math can't drift out of sync between them.
            readonly property int ccHistoryVisibleRows: Math.min(Math.max(pill.notifHistory.length, 1), ccHistoryMaxRows)
            readonly property real ccHistoryListHeight: ccHistoryVisibleRows * ccHistoryRowHeight
                + (ccHistoryVisibleRows - 1) * ccHistoryRowSpacing
            readonly property real ccHistoryListMaxHeight: ccHistoryMaxRows * ccHistoryRowHeight
                + (ccHistoryMaxRows - 1) * ccHistoryRowSpacing

            // Live height for the home view — every section stacked with
            // one ccPadding gap between it and the next, same top/bottom
            // padding reused as the inter-section spacing throughout. A
            // divider sits centered in the tile/slider and slider/history
            // gaps without needing its own extra space.
            // Media card's own slice of the home view — card + its
            // leading gap + trailing divider, but only while ccMediaVisible
            // (playing, or paused within its grace period/while the
            // control center is open — see that property above) — it's
            // fully hidden, not a placeholder, otherwise, see the media
            // card's `visible` binding below.
            readonly property real ccMediaSectionHeight: pill.ccMediaVisible
                ? (ccPadding + ccMediaCardHeight + ccDividerHeight)
                : 0

            readonly property real ccHomeHeight: ccPadding
                + ccTileSize
                + ccPadding
                + ccDividerHeight
                + ccMediaSectionHeight
                + ccSectionLabelHeight
                + ccSectionLabelGap
                + ccSliderRowHeight
                + ccPadding
                + ccSliderRowHeight
                + ccPadding
                + ccHistoryLabelHeight
                + ccHistoryListHeight
                + ccHistoryFooterHeight
                + ccPadding
            // Static upper bound for the same layout (history capped at
            // its max rows, media card assumed visible, instead of the
            // live state) — used only to size the fixed window footprint,
            // same idea as ccWifiMaxRows etc. below.
            readonly property real ccHomeMaxHeight: ccPadding
                + ccTileSize
                + ccPadding
                + ccDividerHeight
                + ccPadding + ccMediaCardHeight + ccDividerHeight
                + ccSectionLabelHeight
                + ccSectionLabelGap
                + ccSliderRowHeight
                + ccPadding
                + ccSliderRowHeight
                + ccPadding
                + ccHistoryLabelHeight
                + ccHistoryListMaxHeight
                + ccHistoryFooterHeight
                + ccPadding

            readonly property real ccWifiHeight: ccSubHeaderHeight
                + Math.min(Math.max(pill.wifiDevice ? pill.wifiDevice.networks.values.length : 0, 1), ccWifiMaxRows) * ccWifiRowHeight
                + ccPadding
            readonly property real ccAudioHeight: ccSubHeaderHeight
                + Math.min(Math.max(pill.audioSinks.length, 1), ccAudioMaxRows) * ccAudioRowHeight
                + ccPadding
            // One row's worth of height even when off/empty — that space
            // is where the "bluetooth is off" / "no paired devices"
            // placeholder text sits, so the sub-view never collapses to
            // just its header.
            readonly property real ccBluetoothHeight: ccSubHeaderHeight
                + Math.min(Math.max(pill.bluetoothPowered ? pill.bluetoothDevices.length : 0, 1), ccBluetoothMaxRows) * ccBluetoothRowHeight
                + ccPadding
            readonly property real ccHeight: ccView === "wifi" ? ccWifiHeight
                : ccView === "audio" ? ccAudioHeight
                : ccView === "bluetooth" ? ccBluetoothHeight
                : ccHomeHeight
            // Upper bound only, for the (static) window footprint — same
            // idea as launcherMaxHeight above.
            readonly property real ccMaxHeight: Math.max(
                ccHomeMaxHeight,
                ccSubHeaderHeight + ccWifiMaxRows * ccWifiRowHeight + ccPadding,
                ccSubHeaderHeight + ccAudioMaxRows * ccAudioRowHeight + ccPadding,
                ccSubHeaderHeight + ccBluetoothMaxRows * ccBluetoothRowHeight + ccPadding)

            function openControlCenter() {
                closeLauncher();
                ccView = "tiles";
                ccOpen = true;
                pinned = false;
                hovered = false;
                refreshBluetoothPower();
                refreshBrightness();
            }

            function closeControlCenter() {
                ccOpen = false;
                if (wifiDevice) wifiDevice.scannerEnabled = false;
                bluetoothPollTimer.stop();
            }

            // --- Power menu (Ctrl+Alt+Delete) ---
            property bool powerMenuOpen: false
            // Which destructive tile (if any) is currently armed awaiting
            // its confirm tap — "" means nothing armed. Safe actions
            // (lock/suspend) never touch this.
            property string armedPmAction: ""

            // Same tile size/spacing/padding the control center's tile
            // row uses, just a flat single row of its own (no header, no
            // sub-view), so it gets its own width/height rather than
            // reusing ccWidth/ccHeight directly.
            readonly property real pmTileSize: ccTileSize
            readonly property real pmTileSpacing: ccTileSpacing
            readonly property real pmPadding: ccPadding
            readonly property int pmTileCount: 5  // Lock, Suspend, Log out, Reboot, Power off
            readonly property real pmWidth: pmPadding * 2
                + pmTileCount * pmTileSize + (pmTileCount - 1) * pmTileSpacing
            readonly property real pmHeight: pmPadding * 2 + pmTileSize

            function openPowerMenu() {
                closeLauncher();
                closeControlCenter();
                armedPmAction = "";
                powerMenuOpen = true;
                pinned = false;
                hovered = false;
            }

            function closePowerMenu() {
                powerMenuOpen = false;
                armedPmAction = "";
                pmArmTimer.stop();
            }

            // Shared by the three destructive tiles: first tap arms the
            // named action (tile goes red, label flips to "Confirm") and
            // starts the reset countdown below; a second tap on that same
            // armed action within the window actually fires it. Tapping
            // any other tile re-arms to that action instead (falls out
            // naturally, since armedPmAction just gets overwritten) rather
            // than needing special-case disarm logic.
            function tapDestructive(action) {
                if (armedPmAction === action) {
                    armedPmAction = "";
                    pmArmTimer.stop();
                    if (action === "logout") logOutSession();
                    else if (action === "reboot") rebootSession();
                    else if (action === "poweroff") powerOffSession();
                    closePowerMenu();
                } else {
                    armedPmAction = action;
                    pmArmTimer.restart();
                }
            }

            // ~3.5s of no follow-up confirm tap resets an armed
            // destructive tile back to normal, per spec, rather than
            // leaving it stuck armed indefinitely.
            Timer {
                id: pmArmTimer
                interval: 3500
                onTriggered: pill.armedPmAction = ""
            }

            // Lock reuses the exact same script SUPER+L already shells
            // out to in hyprland.lua, so there's only ever one lock
            // mechanism in the whole config.
            function lockSession() {
                Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/lock.sh"]);
                closePowerMenu();
            }
            function suspendSession() {
                Quickshell.execDetached(["systemctl", "suspend"]);
                closePowerMenu();
            }
            // Cleanly ends the Hyprland session itself (not just closing
            // windows) — the compositor exiting is what actually logs the
            // session out. This fork of Hyprland is Lua-configured, so
            // `dispatch` takes a Lua expression (hl.dsp.<name>(...)) rather
            // than a bare classic dispatcher name — plain "exit" is not a
            // valid argument and silently no-ops.
            function logOutSession() {
                Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.exit()"]);
            }
            function rebootSession() {
                Quickshell.execDetached(["systemctl", "reboot"]);
            }
            function powerOffSession() {
                Quickshell.execDetached(["systemctl", "poweroff"]);
            }

            // Snapshotted from DesktopEntries.applications rather than
            // re-derived every keystroke — filtering a plain JS array of
            // plain objects is simpler and cheaper than repeatedly walking
            // the live ObjectModel. Refreshed on open and whenever the
            // underlying application set changes (installs/removals).
            property var apps: []

            function reloadApps() {
                apps = DesktopEntries.applications.values
                    .filter(e => !e.noDisplay)
                    .map(e => ({ id: e.id, name: e.name, icon: e.icon, entry: e }))
                    .sort((a, b) => a.name.localeCompare(b.name));
            }

            Component.onCompleted: {
                reloadApps();
                refreshNightLight();
                refreshBluetoothPower();
            }
            Connections {
                target: DesktopEntries
                function onApplicationsChanged() { pill.reloadApps(); }
            }

            // Resolves an app's icon through the real freedesktop
            // icon-theme lookup chain (Quickshell.hasThemeIcon/iconPath —
            // themselves backed by Qt's QIcon::fromTheme resolution:
            // current theme, its inherited parents, hicolor fallback,
            // whatever size/format is actually on disk) rather than
            // guessing a single hardcoded path. Handles the other legal
            // form of a desktop entry's Icon= value too — an absolute
            // path (common for AppImages/Flatpaks/Waydroid apps) — by
            // using it directly instead of running it through the
            // name-based theme lookup, where it could never match.
            // Returns "" when nothing resolves so the caller can fall
            // back to a letter-avatar instead of Quickshell's icon
            // provider handing back its checkerboard "missing" texture
            // for an unresolvable name.
            function resolveIcon(iconName) {
                if (!iconName) return "";
                if (iconName.startsWith("/")) return "file://" + iconName;
                return Quickshell.hasThemeIcon(iconName) ? Quickshell.iconPath(iconName) : "";
            }

            property string launcherQuery: ""

            // Multi-mode via prefix characters, same as a typical launcher:
            // "=" -> calculator, ":" -> clipboard history, anything else
            // -> app filtering. Derived from the raw query, not stored
            // separately, so it can never drift out of sync with it.
            readonly property string launcherMode:
                launcherQuery.startsWith("=") ? "calc"
                : launcherQuery.startsWith(":") ? "clipboard"
                : "apps"
            // The query with its mode prefix stripped — what actually
            // gets matched/evaluated in calc and clipboard mode.
            readonly property string launcherQueryBody:
                launcherMode === "apps" ? launcherQuery : launcherQuery.slice(1)

            // Recomputes reactively off launcherQueryBody/apps — plain
            // substring match, case-insensitive. Capped display
            // (launcherMaxResults) happens per-row, not here, so index
            // stays stable for selection math. Empty outside apps mode so
            // a leftover apps match never lingers behind the calc/
            // clipboard view.
            readonly property var launcherFiltered: launcherMode !== "apps" ? [] : apps.filter(a =>
                launcherQueryBody.length === 0 || a.name.toLowerCase().includes(launcherQueryBody.toLowerCase()))

            // --- Clipboard history mode (":" prefix) ---
            // Raw "<id>\t<preview>" lines from `cliphist list`, refreshed
            // once per launcher open (cheap, and keeps it simple — no need
            // to re-run the CLI on every keystroke just to filter).
            property var clipboardEntries: []

            function refreshClipboard() {
                clipboardListProc.buffer = [];
                clipboardListProc.running = true;
            }

            Process {
                id: clipboardListProc
                property var buffer: []
                command: ["cliphist", "list"]
                stdout: SplitParser {
                    onRead: (line) => clipboardListProc.buffer.push(line)
                }
                onExited: (exitCode, exitStatus) => {
                    if (exitCode === 0) pill.clipboardEntries = clipboardListProc.buffer;
                }
            }

            // Normalized to the same {id, name, icon} shape apps use so
            // the results list/delegate below doesn't need to know which
            // mode it's rendering — `raw` (the untouched "<id>\t<preview>"
            // line cliphist itself needs back) is what tells activateResult
            // apart from an app entry's `entry` (a DesktopEntry).
            readonly property var clipboardFiltered: launcherMode !== "clipboard" ? [] : clipboardEntries
                .map(line => ({ id: line, name: line.replace(/^\d+\t/, ""), icon: "", raw: line }))
                .filter(e => launcherQueryBody.length === 0 || e.name.toLowerCase().includes(launcherQueryBody.toLowerCase()))

            function shellSingleQuoteEscape(str) {
                return str.replace(/'/g, "'\\''");
            }

            function pasteClipboardEntry(entry) {
                if (!entry || !entry.raw) return;
                Quickshell.execDetached(["bash", "-c",
                    `printf '%s' '${shellSingleQuoteEscape(entry.raw)}' | cliphist decode | wl-copy`]);
                closeLauncher();
            }

            // --- Calculator mode ("=" prefix) ---
            property string calcResultText: ""

            function evaluateCalc() {
                // Derives the expression directly from launcherQuery
                // rather than through the launcherQueryBody/launcherMode
                // properties — those are declarative bindings driven off
                // the same launcherQueryChanged signal this function is
                // usually called from, and QML doesn't guarantee they've
                // been re-evaluated yet by the time a plain onChanged
                // handler on the same signal runs (a real, observed bug
                // here: it evaluated one keystroke behind). Reading
                // launcherQuery itself is always current.
                const expr = (launcherQuery.startsWith("=") ? launcherQuery.slice(1) : "").trim();
                if (expr.length === 0) {
                    calcResultText = "";
                    return;
                }
                // Only ever hand a strictly numeric/operator expression to
                // Function() — anything else (identifiers, punctuation)
                // isn't arithmetic and is rejected outright rather than
                // evaluated.
                if (!/^[0-9+\-*/(). ]+$/.test(expr)) return;
                try {
                    const value = Function(`"use strict"; return (${expr});`)();
                    if (typeof value === "number" && isFinite(value)) {
                        calcResultText = Number.isInteger(value)
                            ? value.toString()
                            : parseFloat(value.toFixed(10)).toString();
                    }
                    // else (NaN, e.g. "0/0") — fall through and keep
                    // whatever the last valid result was.
                } catch (e) {
                    // Incomplete expression mid-type (e.g. "3+" or
                    // "(2+3") — keep the last valid result, don't crash
                    // or show an error state.
                }
            }

            function copyCalcResult() {
                if (calcResultText.length === 0) return;
                Quickshell.execDetached(["wl-copy", calcResultText]);
                closeLauncher();
            }

            property int launcherSelectedIndex: 0

            // The single list actually driving the results view —
            // whichever of the two modes' filtered arrays is active, or
            // empty in calc mode (which shows a result line instead of a
            // list).
            readonly property var resultsModel: launcherMode === "clipboard" ? clipboardFiltered : launcherFiltered

            onLauncherQueryChanged: {
                launcherSelectedIndex = 0;
                // Mode is derived inline from launcherQuery here too, for
                // the same reason evaluateCalc() reads launcherQuery
                // directly instead of the launcherMode property — see its
                // comment above.
                const mode = launcherQuery.startsWith("=") ? "calc"
                    : launcherQuery.startsWith(":") ? "clipboard" : "apps";
                if (mode === "calc") evaluateCalc();
                else calcResultText = "";
                if (mode === "clipboard" && clipboardEntries.length === 0) refreshClipboard();
            }
            onResultsModelChanged: launcherSelectedIndex =
                Math.max(0, Math.min(launcherSelectedIndex, resultsModel.length - 1))

            function launchApp(app) {
                if (!app) return;
                app.entry.execute();
                closeLauncher();
            }

            // Dispatches Enter/click on a result row to the right action
            // for whichever mode produced it — an app object carries
            // `.entry` (a DesktopEntry), a clipboard object carries `.raw`
            // instead, so the two are told apart by shape, not by
            // threading the current mode through every call site.
            function activateResult(item) {
                if (!item) return;
                if (item.entry) launchApp(item);
                else if (item.raw !== undefined) pasteClipboardEntry(item);
            }

            function activateLauncher() {
                if (launcherMode === "calc") copyCalcResult();
                else activateResult(resultsModel[launcherSelectedIndex]);
            }

            function openLauncher() {
                closeControlCenter();
                reloadApps();
                launcherQuery = "";
                calcResultText = "";
                launcherSelectedIndex = 0;
                launcherOpen = true;
                pinned = false;
                hovered = false;
            }

            function closeLauncher() {
                launcherOpen = false;
            }

            // Visible result rows before the list scrolls instead of
            // growing further — the pill's height derives directly from
            // this (capped) count, not from the ListView's full (possibly
            // much taller) content height, so the window surface always
            // has a known, sane maximum to size itself to.
            readonly property real launcherListHeight:
                Math.min(resultsModel.length, launcherMaxResults) * launcherRowHeight
            // Calc mode shows one short result line instead of a list —
            // only tall enough to hold it, and only once there is one.
            readonly property real launcherCalcHeight: calcResultText.length > 0 ? 48 : 0

            // Same critically damped spring drives every size change here,
            // including the OSD's and the launcher's — collapsed <-> OSD
            // <-> expanded <-> launcher are all just different targets for
            // the one Behavior below.
            width: launcherOpen ? launcherWidth : (ccOpen ? ccWidth : (powerMenuOpen ? pmWidth : (expanded ? expandedWidth : (notifVisible ? notifWidth : (osdVisible ? osdWidth : collapsedWidth)))))
            height: launcherOpen
                ? launcherHeaderHeight + (launcherMode === "calc"
                    ? launcherCalcHeight
                    : launcherListHeight + launcherListPadding * 2)
                : (ccOpen ? ccHeight : (powerMenuOpen ? pmHeight : (expanded ? expandedHeight : (notifVisible ? notifHeight : collapsedHeight))))

            // Fast move, no overshoot, no bounce — same character as a
            // critically damped spring, but a fixed-duration NumberAnimation
            // instead of an actual spring simulation specifically so this
            // has a known, exact total time. A SpringAnimation's settle
            // time isn't a fixed number — it depends on how far width/
            // height are travelling, so it drifts transition to transition
            // (e.g. collapsed->launcher vs expanded->launcher cover very
            // different distances). That mismatch is exactly what made the
            // launcher's container and its content (a separate, genuinely
            // fixed-duration opacity fade below) finish at visibly
            // different times. Pinning both to the same 250ms duration
            // keeps every pill morph — hover-expand, OSD, launcher alike —
            // landing together, every time, regardless of distance.
            Behavior on width {
                NumberAnimation {
                    duration: 250
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on height {
                NumberAnimation {
                    duration: 250
                    easing.type: Easing.OutCubic
                }
            }

            RectangularShadow {
                anchors.fill: bg
                radius: bg.radius
                blur: 14
                spread: -2
                offset: Qt.vector2d(0, 2)
                color: "#66000000"
            }

            Rectangle {
                id: bg
                anchors.fill: parent
                // height/2 gives the collapsed/expanded-media pill its
                // fully-rounded stadium ends — correct there because those
                // states stay short. The launcher state can grow tall
                // (header + several result rows), where height/2 would
                // blow up into a huge radius and render as a near-circle
                // instead of a normal rounded rectangle, so it gets its
                // own fixed, reasonable corner radius instead.
                radius: (pill.launcherOpen || pill.ccOpen || pill.powerMenuOpen) ? 20 : height / 2
                color: Colors.background
                // Critical notifications get a red accent border instead
                // of the usual neutral outline while their popup card is
                // actually showing — same red as the wifi/bluetooth
                // glyphs' disabled strike-through, reused here as the
                // shell's one "urgent" accent rather than inventing a
                // second one.
                border.color: (pill.notifVisible && pill.activeNotif?.critical && !pill.expanded && !pill.launcherOpen && !pill.ccOpen && !pill.powerMenuOpen)
                    ? Colors.critical : Colors.border
                border.width: 1

                Behavior on border.color { ColorAnimation { duration: 150 } }
            }

            // Empty-space layer: sits under everything else. Clicking here
            // toggles pin. Actual controls (below, drawn on top) have their
            // own MouseAreas that consume the click first, so they fire
            // their action instead of toggling pin.
            //
            // Hover detection lives in `hoverZone` below, not in this
            // MouseArea. Both hoverZone and this MouseArea are sized to the
            // full expanded footprint and anchored the same fixed way pill
            // itself is (top + horizontal center, neither ever animated) —
            // never resized or repositioned. Getting there took a few
            // broken attempts, left here as a map of the dead ends:
            //   - Sizing the hit-box to pill's current target jumped
            //     instantly between collapsed/expanded and disagreed with
            //     the still-animating visible pill mid-transition.
            //   - Animating the hit-box's own width/height with a matching
            //     spring just created a second spring chasing
            //     `pill.expanded`, which is itself driven by this hit-box's
            //     hover state — two independently-animated springs feeding
            //     each other desync mid-flight and oscillate.
            //   - A static hit-box driving pill.hovered off its own
            //     MouseArea entered/exited still broke: those follow Qt
            //     Quick's exclusive/topmost-item hover delivery, and the
            //     expanded content stacked on top (crossfaded via opacity,
            //     but still present and still hit-testable even at opacity
            //     0) silently steals hover the instant `expanded` flips,
            //     firing a spurious exited right back — another
            //     oscillation. Swapping in a HoverHandler alone didn't fix
            //     this either, since Qt Quick still only delivers hover to
            //     the topmost item and that same content still shadowed it.
            //
            // `hoverZone` fixes this by sitting in a raised z-layer above
            // that content, purely to host the HoverHandler — always the
            // topmost thing under the cursor, so it can never be shadowed.
            // `z` only affects event/paint stacking, so this doesn't block
            // clicks reaching the (lower, unraised) MouseArea below or the
            // real controls above it — a HoverHandler only observes, it
            // never grabs. `overPill` is a plain property binding (not an
            // imperative signal handler), so it re-evaluates automatically
            // on any relevant change — pointer position, or pill.width/
            // height moving mid-animation — comparing the cursor against
            // pill's real, currently-rendered (possibly mid-animation) size
            // via a rect-contains check anchored to hoverZone's own fixed
            // origin. osdVisible never enters this math, so an OSD-driven
            // width change still can't move the hover boundary.
            Item {
                id: hoverZone
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                width: pill.expandedWidth
                height: pill.expandedHeight
                z: 1
                // While the launcher or control center is open, it owns
                // the pill's input entirely — this hover layer would
                // otherwise sit on top of it (z: 1) and steal clicks/hover
                // meant for that surface's own content. Same reasoning
                // for a showing notification: it has its own hover/click
                // handling below (pause-countdown / dismiss), and letting
                // this generic layer keep setting pill.hovered underneath
                // it would force pill.expanded true and yank the width
                // over to expandedWidth mid-notification.
                enabled: !pill.launcherOpen && !pill.ccOpen && !pill.notifVisible && !pill.powerMenuOpen

                readonly property real pillLeft: (width - pill.width) / 2
                readonly property bool overPill: hoverTracker.hovered
                    && hoverTracker.point.position.x >= pillLeft
                    && hoverTracker.point.position.x <= pillLeft + pill.width
                    && hoverTracker.point.position.y >= 0
                    && hoverTracker.point.position.y <= pill.height

                // The write into pill.hovered is gated on hoverZone being
                // "enabled" (not launcher/cc/notification owning input),
                // but hoverTracker itself below stays live regardless —
                // see the comment on it for why. That split matters here:
                // gating the write, not the tracking, is what lets
                // closeActiveNotif() below read a genuinely fresh
                // overPill the instant a notification closes, instead of
                // whatever pill.hovered was last written to.
                onOverPillChanged: if (hoverZone.enabled) pill.hovered = overPill

                // Deliberately NOT gated by `enabled: hoverZone.enabled`.
                // HoverHandler doesn't inherit the enclosing Item's
                // `enabled: false` the way MouseArea does — it's a
                // separate PointerHandler with its own enabled state —
                // and disabling it here would freeze its hovered/position
                // at whatever they were the instant it got disabled,
                // rather than the real live cursor state. That staleness
                // bit twice: once while a notification was showing (the
                // frozen "already hovering" reading forced pill.expanded
                // true and hid the popup behind the hover-expand view —
                // fixed by gating the *write* above instead), and again
                // the instant a notification closed (re-enabling here
                // would have resumed from that same stale frozen value
                // rather than the mouse's actual current position,
                // spuriously expanding the pill right after dismiss).
                // Leaving this always-live and gating only the write
                // above fixes both: overPill is always an honest read of
                // the real cursor, whether or not it's currently allowed
                // to drive pill.hovered.
                HoverHandler {
                    id: hoverTracker
                }
            }

            MouseArea {
                id: background
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                width: pill.expandedWidth
                height: pill.expandedHeight
                enabled: !pill.launcherOpen && !pill.ccOpen && !pill.notifVisible && !pill.powerMenuOpen
                onClicked: if (hoverZone.overPill) pill.pinned = !pill.pinned
            }

            // Collapsed-state content: EQ bars (only while music is
            // playing) + clock. Crossfades against the zones Row below as
            // the pill expands/collapses, and against the volume OSD when
            // that's showing.
            Row {
                id: collapsed
                anchors.centerIn: parent
                // Spacing itself animates to 0 so the bars leave no dead
                // gap once they've fully collapsed away.
                spacing: pill.musicPlaying ? 6 : 0
                visible: opacity > 0
                opacity: (pill.expanded || pill.osdVisible || pill.notifVisible || pill.launcherOpen || pill.ccOpen || pill.powerMenuOpen) ? 0 : 1

                Behavior on spacing {
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutQuad
                    }
                }
                Behavior on opacity {
                    NumberAnimation {
                        duration: 160
                        easing.type: Easing.OutQuad
                    }
                }

                // EQ bars — a looping pseudo-random "alive" animation, not
                // real frequency data (matches the reference).
                Item {
                    id: eqBars
                    width: pill.musicPlaying ? 4 * 6 - 3 : 0
                    height: 16
                    clip: true
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: pill.musicPlaying ? 1 : 0

                    Behavior on width {
                        NumberAnimation {
                            duration: 200
                            easing.type: Easing.OutQuad
                        }
                    }
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 200
                            easing.type: Easing.OutQuad
                        }
                    }

                    Repeater {
                        model: 4

                        delegate: Rectangle {
                            id: bar
                            required property int index

                            x: index * 6
                            width: 3
                            radius: 1.5
                            height: 4
                            color: Colors.accent
                            anchors.bottom: parent.bottom

                            Behavior on height {
                                NumberAnimation {
                                    duration: 150
                                    easing.type: Easing.InOutQuad
                                }
                            }

                            // Each bar randomizes on its own slightly
                            // different cadence so they don't all move in
                            // lockstep — reads as more organic.
                            Timer {
                                interval: 140 + Math.random() * 120
                                running: pill.musicPlaying
                                repeat: true
                                triggeredOnStart: true
                                onTriggered: bar.height = 3 + Math.random() * 13
                            }
                        }
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Qt.formatDateTime(clock.now, "h:mm AP")
                    color: Colors.text
                    font.pixelSize: 13
                }
            }

            // Volume OSD — collapsed-state only. Morphs the pill into
            // icon + fill bar + percentage while the volume is being
            // changed (the pill itself widens to osdWidth for this, see
            // the width binding above), then melts back to the clock/EQ
            // view. Icon pinned left, percentage pinned right, bar fills
            // whatever's left between them — so it reads as one wide
            // level meter rather than a cluster stuck in the middle.
            Item {
                id: osd
                anchors.fill: parent
                visible: opacity > 0
                opacity: (pill.expanded || !pill.osdVisible || pill.notifVisible || pill.launcherOpen || pill.ccOpen || pill.powerMenuOpen) ? 0 : 1

                Behavior on opacity {
                    NumberAnimation {
                        duration: 160
                        easing.type: Easing.OutQuad
                    }
                }

                // Plain/simple speaker glyph for now — a single hand-drawn
                // shape (Canvas, not an icon font), no muted/loud states
                // yet; that's a later phase.
                Canvas {
                    id: osdIcon
                    width: 14
                    height: 14
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter

                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        ctx.fillStyle = Colors.text;
                        ctx.beginPath();
                        ctx.moveTo(0, 5);
                        ctx.lineTo(4, 5);
                        ctx.lineTo(8, 1);
                        ctx.lineTo(8, 13);
                        ctx.lineTo(4, 9);
                        ctx.lineTo(0, 9);
                        ctx.closePath();
                        ctx.fill();
                    }
                }

                Text {
                    id: osdPercent
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: pill.sink?.audio.muted ? "Muted" : Math.round((pill.sink?.audio.volume ?? 0) * 100) + "%"
                    color: Colors.text
                    font.pixelSize: 12
                }

                Item {
                    anchors.left: osdIcon.right
                    anchors.leftMargin: 10
                    anchors.right: osdPercent.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    height: 6

                    Rectangle {
                        anchors.fill: parent
                        radius: 3
                        color: Colors.border
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        height: parent.height
                        radius: 3
                        color: Colors.accent
                        width: parent.width * Math.max(0, Math.min(1, pill.sink?.audio.muted ? 0 : (pill.sink?.audio.volume ?? 0)))

                        Behavior on width {
                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.OutQuad
                            }
                        }
                    }
                }
            }

            // Notification popup — collapsed-state-only morph (same
            // pattern as the volume OSD above), showing whichever
            // notification just came in: app icon, or a themed
            // letter-avatar when the app didn't supply one, plus summary
            // and body. Hovering anywhere on it pauses the auto-dismiss
            // countdown (notifTickTimer, defined with the rest of the
            // notification state up in `pill`); moving away resumes it;
            // clicking it dismisses early.
            Item {
                id: notifCard
                anchors.fill: parent
                visible: opacity > 0
                opacity: (pill.expanded || !pill.notifVisible || pill.launcherOpen || pill.ccOpen) ? 0 : 1

                Behavior on opacity {
                    NumberAnimation {
                        duration: 160
                        easing.type: Easing.OutQuad
                    }
                }

                readonly property var notif: pill.activeNotif
                readonly property string iconSource: pill.resolveIcon(notif?.appIcon ?? "")

                HoverHandler {
                    onHoveredChanged: pill.notifHovered = hovered
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: pill.closeActiveNotif(true)
                }

                Item {
                    id: notifIconArea
                    width: 28
                    height: 28
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter

                    IconImage {
                        id: notifIcon
                        anchors.fill: parent
                        implicitSize: 28
                        visible: notifCard.iconSource.length > 0
                        source: notifCard.iconSource
                    }

                    // Themed letter-avatar fallback — same idea as the
                    // launcher's resultRow above, shown only when no icon
                    // actually resolved.
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        visible: !notifIcon.visible
                        color: pill.notifAvatarColor(notifCard.notif?.appName ?? "?")

                        Text {
                            anchors.centerIn: parent
                            text: (notifCard.notif?.appName ?? "?").charAt(0).toUpperCase()
                            color: "#ffffff"
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                    }
                }

                Column {
                    anchors.left: notifIconArea.right
                    anchors.leftMargin: 10
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        width: parent.width
                        text: notifCard.notif?.summary || notifCard.notif?.appName || ""
                        color: Colors.text
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        visible: (notifCard.notif?.body ?? "").length > 0
                        text: notifCard.notif?.body ?? ""
                        color: Colors.textTertiary
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                }
            }

            // Anchored (not a centering Row) so the center zone stays
            // dead-center in the pill no matter how wide the left zone's
            // content gets — a Row would recenter the whole cluster and
            // drag the clock off-center whenever media controls appear.
            Item {
                id: zones
                anchors.fill: parent
                visible: opacity > 0
                opacity: (pill.expanded && !pill.launcherOpen && !pill.ccOpen && !pill.powerMenuOpen) ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: 160
                        easing.type: Easing.OutQuad
                    }
                }

                // LEFT ZONE — media controls while a player is actually
                // playing (reuses pill.musicPlaying/activePlayer, same
                // gate as the EQ bars), otherwise a lighthearted "No
                // track" placeholder instead of just reserved empty space.
                // Always at its full footprint — the two Rows inside
                // crossfade against each other rather than the zone itself
                // animating width/opacity in and out.
                Item {
                    id: leftZone
                    anchors.left: parent.left
                    anchors.leftMargin: 24
                    anchors.verticalCenter: parent.verticalCenter
                    width: 210
                    // Tall enough for the enlarged album art to sit
                    // comfortably centered within the expanded pill,
                    // rather than the old fixed 34 (a leftover from when
                    // this zone only held a 24px thumbnail + button row).
                    height: 52
                    clip: true

                    Row {
                        id: mediaRow
                        spacing: 12
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        visible: opacity > 0
                        opacity: pill.musicPlaying ? 1 : 0

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 200
                                easing.type: Easing.OutQuad
                            }
                        }

                        // Album art — the visual anchor of this zone now
                        // that the transport buttons are gone. Rounded via
                        // an OpacityMask (Qt5Compat.GraphicalEffects, same
                        // pattern used elsewhere in this config) since
                        // Image doesn't clip to radius on its own. Hidden
                        // entirely (not a placeholder box) when the player
                        // doesn't report art.
                        Item {
                            id: albumArtMask
                            width: 48
                            height: 48
                            anchors.verticalCenter: parent.verticalCenter
                            visible: albumArt.status === Image.Ready

                            Image {
                                id: albumArt
                                anchors.fill: parent
                                source: pill.activePlayer?.trackArtUrl ?? ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                smooth: true
                                cache: false
                            }

                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle {
                                    width: albumArtMask.width
                                    height: albumArtMask.height
                                    radius: 10
                                }
                            }
                        }

                        Column {
                            width: 140
                            spacing: 4
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                width: parent.width
                                text: root.cleanMediaText(pill.activePlayer?.trackTitle ?? "")
                                color: Colors.text
                                font.pixelSize: 13
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: root.cleanMediaText(pill.activePlayer?.trackArtist ?? "")
                                color: Colors.textTertiary
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }
                    }

                    // "No track" placeholder — replaces the old bare
                    // reserved space. A plain hand-drawn disc glyph
                    // (Canvas, not an icon font — same approach as the
                    // volume OSD's speaker icon elsewhere in this file),
                    // lighthearted rather than a literal DVD-logo asset.
                    Row {
                        spacing: 12
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        visible: opacity > 0
                        opacity: pill.musicPlaying ? 0 : 1

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 200
                                easing.type: Easing.OutQuad
                            }
                        }

                        Canvas {
                            id: noTrackIcon
                            width: 22
                            height: 22
                            anchors.verticalCenter: parent.verticalCenter

                            onPaint: {
                                const ctx = getContext("2d");
                                ctx.reset();
                                const cx = width / 2, cy = height / 2;
                                const r = Math.min(width, height) / 2 - 1;
                                ctx.strokeStyle = Colors.iconMuted;
                                ctx.lineWidth = 1.5;
                                ctx.beginPath();
                                ctx.arc(cx, cy, r, 0, Math.PI * 2);
                                ctx.stroke();
                                ctx.beginPath();
                                ctx.fillStyle = Colors.iconMuted;
                                ctx.arc(cx, cy, r * 0.35, 0, Math.PI * 2);
                                ctx.fill();
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "No track"
                            color: Colors.textDisabled
                            font.pixelSize: 13
                        }
                    }
                }

                // CENTER ZONE — hero clock + today's date. Always
                // dead-center in the pill (see the zones Item's anchoring
                // note above).
                Column {
                    anchors.centerIn: parent
                    width: 200
                    spacing: 2

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatDateTime(clock.now, "h:mm AP")
                        color: Colors.text
                        font.pixelSize: 24
                        font.weight: Font.DemiBold
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatDateTime(clock.now, "dddd, MMMM d")
                        color: Colors.textTertiary
                        font.pixelSize: 12
                    }
                }

                // RIGHT ZONE — status icons. Both wifi and battery are
                // hand-drawn Canvas glyphs (matching the volume OSD icon
                // and the "no track" glyph above, not an icon font) and
                // both are themselves live meters rather than static
                // symbols: the wifi glyph's arcs fill in with signal
                // strength, the battery's fill bar tracks charge level.
                // Bluetooth/other icons are skipped for now — no clean
                // native data source wired up yet.
                Item {
                    anchors.right: parent.right
                    anchors.rightMargin: 24
                    anchors.verticalCenter: parent.verticalCenter
                    width: 86
                    height: 34

                    Row {
                        anchors.centerIn: parent
                        spacing: 10

                        // Network — see the NetworkGlyph component above.
                        NetworkGlyph {
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        // Battery — iOS-style cell: percentage sits INSIDE
                        // the outline, and the fill bar behind that text is
                        // the actual charge level. Turns green + grows a
                        // bolt glyph while charging, red when low and not
                        // charging. Hidden entirely (not a fake 0%) when
                        // UPower reports no real battery, e.g. desktops.
                        Item {
                            id: batteryCell
                            visible: pill.batteryPresent
                            width: visible ? 34 : 0
                            height: 16
                            anchors.verticalCenter: parent.verticalCenter
                            clip: true

                            Canvas {
                                id: batteryIcon
                                anchors.fill: parent

                                readonly property real pct: Math.max(0, Math.min(100, pill.batteryPct))
                                readonly property bool charging: pill.batteryCharging

                                onPctChanged: requestPaint()
                                onChargingChanged: requestPaint()
                                Component.onCompleted: requestPaint()

                                onPaint: {
                                    const ctx = getContext("2d");
                                    ctx.reset();

                                    const bodyX = 0, bodyY = 1;
                                    const bodyW = width - 4;
                                    const bodyH = height - 2;

                                    // Charge fill sits behind the outline,
                                    // inset from it, so the outline always
                                    // stays crisp on top of it.
                                    const inset = 2;
                                    const fillMaxW = bodyW - inset * 2;
                                    const fillW = fillMaxW * (pct / 100);
                                    const fillColor = charging ? Colors.success : (pct <= 20 ? Colors.critical : Colors.accent);
                                    if (fillW > 0.5) {
                                        root.roundedRectPath(ctx, bodyX + inset, bodyY + inset, fillW, bodyH - inset * 2, 1.5);
                                        ctx.fillStyle = fillColor;
                                        ctx.fill();
                                    }

                                    root.roundedRectPath(ctx, bodyX, bodyY, bodyW, bodyH, 3);
                                    ctx.strokeStyle = Colors.textDisabled;
                                    ctx.lineWidth = 1.2;
                                    ctx.stroke();

                                    // Terminal nub.
                                    root.roundedRectPath(ctx, bodyX + bodyW + 1, height / 2 - 3, 2.5, 6, 1);
                                    ctx.fillStyle = Colors.textDisabled;
                                    ctx.fill();

                                    // Bolt glyph while charging, drawn on
                                    // top of the fill, left of where the
                                    // percentage text sits.
                                    if (charging) {
                                        ctx.beginPath();
                                        ctx.moveTo(bodyX + bodyW * 0.42, bodyY + 1);
                                        ctx.lineTo(bodyX + bodyW * 0.28, bodyY + bodyH * 0.58);
                                        ctx.lineTo(bodyX + bodyW * 0.40, bodyY + bodyH * 0.58);
                                        ctx.lineTo(bodyX + bodyW * 0.30, bodyY + bodyH - 1);
                                        ctx.lineTo(bodyX + bodyW * 0.56, bodyY + bodyH * 0.40);
                                        ctx.lineTo(bodyX + bodyW * 0.44, bodyY + bodyH * 0.40);
                                        ctx.closePath();
                                        ctx.fillStyle = Colors.background;
                                        ctx.fill();
                                    }
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: Math.round(batteryIcon.pct) + "%"
                                color: Colors.text
                                font.pixelSize: 8
                                font.weight: Font.DemiBold
                            }
                        }
                    }
                }
            }

            // APP LAUNCHER (SUPER+SPACE) — the pill morphs directly into
            // this, the same way it morphs into the volume OSD: one more
            // target for the width/height Behaviors above, not a separate
            // window. Crossfades against collapsed/OSD/zones via the
            // opacity guards already added to each of those.
            Item {
                id: launcher
                anchors.fill: parent
                visible: opacity > 0
                opacity: pill.launcherOpen ? 1 : 0

                // Same 250ms/easing as the container's width/height
                // Behavior above — content and shape are driven by
                // different properties (opacity vs size) so they can't
                // share one literal animation node, but matching duration
                // and easing means they still start together (both react
                // to launcherOpen flipping) and land together.
                Behavior on opacity {
                    NumberAnimation {
                        duration: 250
                        easing.type: Easing.OutCubic
                    }
                }

                // Real text cursor hidden — the launcher is fully
                // keyboard-driven via arrow keys/Enter, not a blinking
                // caret. Selection highlight in the list below is the
                // only "where am I" indicator.
                Item {
                    id: launcherHeader
                    width: parent.width
                    height: pill.launcherHeaderHeight

                    TextInput {
                        id: launcherField
                        anchors.fill: parent
                        anchors.leftMargin: 18
                        anchors.rightMargin: 18
                        verticalAlignment: TextInput.AlignVCenter
                        color: Colors.text
                        font.pixelSize: 15
                        cursorVisible: false
                        clip: true

                        onTextChanged: pill.launcherQuery = text

                        Keys.onEscapePressed: pill.closeLauncher()
                        Keys.onReturnPressed: pill.activateLauncher()
                        Keys.onEnterPressed: pill.activateLauncher()
                        Keys.onUpPressed: pill.launcherSelectedIndex = Math.max(0, pill.launcherSelectedIndex - 1)
                        Keys.onDownPressed: pill.launcherSelectedIndex =
                            Math.min(pill.resultsModel.length - 1, pill.launcherSelectedIndex + 1)

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Search apps… (\"=\" calculator, \":\" clipboard)"
                            color: Colors.textDisabled
                            font.pixelSize: 15
                            visible: launcherField.text.length === 0
                        }
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 18
                        anchors.rightMargin: 18
                        height: 1
                        color: Colors.border
                        visible: pill.launcherMode === "calc" ? pill.calcResultText.length > 0 : launcherResults.count > 0
                    }
                }

                // Calculator mode — a live result line instead of a list.
                // Shown/hidden by height alone (0 when there's nothing
                // valid to show yet), matching pill.launcherCalcHeight
                // above so the pill never has dead space reserved for it.
                Item {
                    id: calcResultView
                    anchors.top: launcherHeader.bottom
                    width: parent.width
                    height: pill.launcherMode === "calc" ? pill.launcherCalcHeight : 0
                    visible: height > 0
                    clip: true

                    Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 18
                        anchors.rightMargin: 18
                        text: "= " + pill.calcResultText
                        color: Colors.success
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                }

                // A real ListView, not a Column of always-present rows —
                // its height is capped at pill.launcherListHeight (at most
                // launcherMaxResults rows tall, matching the pill's own
                // height binding above), so the window surface always has
                // a known, sane maximum to size itself to. Any additional
                // matches beyond that scroll into view instead of forcing
                // the pill to keep growing or overflowing its surface.
                // add/remove/displaced transitions replace the old
                // "every row always exists, animate height to 0" trick now
                // that rows genuinely enter/leave the model on each
                // keystroke — same fade + slide-into-place feel. Used for
                // both apps and clipboard-history mode — pill.resultsModel
                // is whichever of the two is active (empty in calc mode).
                ListView {
                    id: launcherResults
                    anchors.top: launcherHeader.bottom
                    width: parent.width
                    height: pill.launcherMode === "calc" ? 0 : pill.launcherListHeight
                    visible: height > 0
                    topMargin: pill.launcherListPadding
                    bottomMargin: pill.launcherListPadding
                    clip: true
                    model: pill.resultsModel
                    currentIndex: pill.launcherSelectedIndex
                    highlightFollowsCurrentItem: true
                    highlightMoveDuration: 150

                    add: Transition {
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 160; easing.type: Easing.OutQuad }
                    }
                    remove: Transition {
                        NumberAnimation { property: "opacity"; to: 0; duration: 120; easing.type: Easing.OutQuad }
                    }
                    displaced: Transition {
                        NumberAnimation { properties: "y"; duration: 180; easing.type: Easing.OutQuad }
                    }

                    delegate: Item {
                        id: resultRow
                        required property var modelData
                        required property int index

                        readonly property bool selected: index === pill.launcherSelectedIndex
                        readonly property string iconSource: pill.resolveIcon(modelData.icon)

                        width: ListView.view.width
                        height: pill.launcherRowHeight

                        Rectangle {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            anchors.topMargin: 2
                            anchors.bottomMargin: 2
                            radius: 8
                            color: resultRow.selected ? Colors.border : "transparent"

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 12

                                IconImage {
                                    id: appIcon
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 22
                                    height: 22
                                    implicitSize: 22
                                    visible: resultRow.iconSource.length > 0
                                    source: resultRow.iconSource
                                }

                                // Letter-avatar fallback — shown only
                                // when no icon actually resolved
                                // through the theme lookup chain, so we
                                // never hand the image provider a name
                                // it can't find (that renders as an
                                // ugly checkerboard "missing" texture
                                // rather than nothing). Same idea as
                                // the notification spec's themed
                                // letter-avatar fallback.
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 22
                                    height: 22
                                    radius: 11
                                    visible: !appIcon.visible
                                    color: Qt.hsla(
                                        (Array.from(resultRow.modelData.name)
                                            .reduce((sum, ch) => sum + ch.charCodeAt(0), 0) % 360) / 360,
                                        0.45, 0.35, 1)

                                    Text {
                                        anchors.centerIn: parent
                                        text: resultRow.modelData.name.charAt(0).toUpperCase()
                                        color: "#ffffff"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                    }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 22 - 12
                                    text: resultRow.modelData.name
                                    color: Colors.text
                                    font.pixelSize: 13
                                    elide: Text.ElideRight
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    pill.launcherSelectedIndex = resultRow.index;
                                    pill.activateResult(resultRow.modelData);
                                }
                            }
                        }
                    }
                }
            }

            // CONTROL CENTER (Alt+A) — same morph pattern as the launcher:
            // toggle tiles up top, tapping a tile's body (not its icon)
            // slides in that tile's sub-view, island resizing to fit.
            // Escape from any page returns to the collapsed pill.
            Item {
                id: controlCenter
                anchors.fill: parent
                visible: opacity > 0
                opacity: pill.ccOpen ? 1 : 0

                // Same 250ms/easing as the container's width/height
                // Behavior and the launcher's own opacity fade above, for
                // the same lockstep-timing reason.
                Behavior on opacity {
                    NumberAnimation {
                        duration: 250
                        easing.type: Easing.OutCubic
                    }
                }

                // Invisible focus target so Escape works from anywhere in
                // this surface — unlike the launcher, there's no text
                // field here to naturally anchor keyboard focus to.
                Item {
                    id: ccKeyCatcher
                    anchors.fill: parent
                    Keys.onEscapePressed: pill.closeControlCenter()
                }

                // The three pages sit side by side in one wide row; only
                // the ccWidth-wide window onto it (the clipping Item
                // below) stays put while the row slides under it — the
                // spec's "sub-views slide/push in" behavior.
                Item {
                    anchors.fill: parent
                    clip: true

                    Row {
                        id: ccPages
                        x: -pill.ccViewIndex * pill.ccWidth

                        Behavior on x {
                            NumberAnimation {
                                duration: 250
                                easing.type: Easing.OutCubic
                            }
                        }

                        // PAGE 0 — home view: tile grid, volume/brightness
                        // sliders, and notification history, all visible
                        // together (Android-quick-settings style) rather
                        // than split across taps. Wifi/audio/bluetooth
                        // device lists are still their own slide-in pages
                        // below — opened by tapping those tiles — since
                        // they need actual back-navigation.
                        Item {
                            id: ccHome
                            width: pill.ccWidth
                            height: pill.ccHomeHeight

                            Row {
                                id: ccTileRow
                                anchors.top: parent.top
                                anchors.topMargin: pill.ccPadding
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: pill.ccTileSpacing

                                // WIFI tile — split-tap: icon toggles the
                                // radio directly, the rest of the tile
                                // opens the network list.
                                Item {
                                    width: pill.ccTileSize
                                    height: pill.ccTileSize

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 16
                                        color: Networking.wifiEnabled ? Colors.accentContainer : Colors.surfaceContainer
                                        border.color: Networking.wifiEnabled ? Colors.accent : Colors.border
                                        border.width: 1

                                        Behavior on color { ColorAnimation { duration: 150 } }
                                    }

                                    // Whole-tile tap opens the sub-view.
                                    // The icon's own MouseArea below is a
                                    // sibling declared later, so it sits on
                                    // top and wins for its own bounds —
                                    // same empty-space-vs-control split
                                    // used at the top of this file.
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: pill.ccView = "wifi"
                                    }

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 6

                                        Item {
                                            width: 28
                                            height: 22
                                            anchors.horizontalCenter: parent.horizontalCenter

                                            NetworkGlyph {
                                                anchors.centerIn: parent
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
                                            }
                                        }

                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: "Wifi"
                                            color: Colors.text
                                            font.pixelSize: 11
                                            font.weight: Font.Medium
                                        }
                                    }
                                }

                                // AUDIO tile — icon mutes/unmutes directly,
                                // rest of the tile opens the device list.
                                Item {
                                    id: audioTile
                                    width: pill.ccTileSize
                                    height: pill.ccTileSize

                                    readonly property bool unmuted: !(pill.sink?.audio.muted ?? true)

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 16
                                        color: audioTile.unmuted ? Colors.accentContainer : Colors.surfaceContainer
                                        border.color: audioTile.unmuted ? Colors.accent : Colors.border
                                        border.width: 1

                                        Behavior on color { ColorAnimation { duration: 150 } }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: pill.ccView = "audio"
                                    }

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 6

                                        Item {
                                            width: 28
                                            height: 22
                                            anchors.horizontalCenter: parent.horizontalCenter

                                            AudioGlyph {
                                                anchors.centerIn: parent
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: {
                                                    if (pill.sink) pill.sink.audio.muted = !pill.sink.audio.muted;
                                                }
                                            }
                                        }

                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: "Audio"
                                            color: Colors.text
                                            font.pixelSize: 11
                                            font.weight: Font.Medium
                                        }
                                    }
                                }

                                // NIGHT LIGHT tile — simple on/off, no
                                // sub-view, so the whole tile (icon
                                // included) shares one action.
                                Item {
                                    width: pill.ccTileSize
                                    height: pill.ccTileSize

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 16
                                        color: pill.nightLightActive ? Colors.warningContainer : Colors.surfaceContainer
                                        border.color: pill.nightLightActive ? Colors.warning : Colors.border
                                        border.width: 1

                                        Behavior on color { ColorAnimation { duration: 150 } }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: pill.toggleNightLight()
                                    }

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 6

                                        NightLightGlyph {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            active: pill.nightLightActive
                                        }

                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: "Night"
                                            color: Colors.text
                                            font.pixelSize: 11
                                            font.weight: Font.Medium
                                        }
                                    }
                                }

                                // BLUETOOTH tile — split-tap: icon toggles
                                // the radio directly, rest of the tile
                                // opens the paired-device list. Same
                                // pattern as the wifi tile above; only the
                                // glyph and backing state differ.
                                Item {
                                    width: pill.ccTileSize
                                    height: pill.ccTileSize

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 16
                                        color: pill.bluetoothPowered ? Colors.accentContainer : Colors.surfaceContainer
                                        border.color: pill.bluetoothPowered ? Colors.accent : Colors.border
                                        border.width: 1

                                        Behavior on color { ColorAnimation { duration: 150 } }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: pill.ccView = "bluetooth"
                                    }

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 6

                                        Item {
                                            width: 28
                                            height: 22
                                            anchors.horizontalCenter: parent.horizontalCenter

                                            BluetoothGlyph {
                                                anchors.centerIn: parent
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: pill.toggleBluetoothPower()
                                            }
                                        }

                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            width: pill.ccTileSize - 8
                                            horizontalAlignment: Text.AlignHCenter
                                            text: "Bluetooth"
                                            color: Colors.text
                                            font.pixelSize: 11
                                            font.weight: Font.Medium
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                // PEACE (do-not-disturb) tile — plain
                                // on/off, no sub-view, same single-action
                                // whole-tile tap as Night Light. Turning
                                // it on doesn't touch history — it only
                                // suppresses the popup morph on new
                                // notifications (see NotificationServer's
                                // onNotification, defined with the rest
                                // of the notification state up in `pill`).
                                Item {
                                    width: pill.ccTileSize
                                    height: pill.ccTileSize

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 16
                                        color: pill.peaceMode ? Colors.accentContainer : Colors.surfaceContainer
                                        border.color: pill.peaceMode ? Colors.accent : Colors.border
                                        border.width: 1

                                        Behavior on color { ColorAnimation { duration: 150 } }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: pill.peaceMode = !pill.peaceMode
                                    }

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 6

                                        PeaceGlyph {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            active: pill.peaceMode
                                        }

                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: "Peace"
                                            color: Colors.text
                                            font.pixelSize: 11
                                            font.weight: Font.Medium
                                        }
                                    }
                                }
                            }

                            // Hairline divider + "Quick Settings" label —
                            // purely visual section break so the tile grid
                            // doesn't blend into the sliders below it. Same
                            // low-opacity line reused before the
                            // notifications section further down.
                            Rectangle {
                                id: tileDivider
                                anchors.top: ccTileRow.bottom
                                anchors.topMargin: pill.ccPadding / 2
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: pill.ccPadding
                                anchors.rightMargin: pill.ccPadding
                                height: pill.ccDividerHeight
                                color: Colors.borderHover
                                opacity: 0.5
                            }

                            // MEDIA CARD — its own section between the
                            // tile grid and the quick-settings sliders,
                            // matching the spec's blurred-art-background
                            // player card. Gated on pill.ccMediaVisible —
                            // a separate "sticky" gate from
                            // musicPlaying/activePlayer (which still
                            // drive the pill's own collapsed EQ bars and
                            // expanded media zone unchanged) — so the
                            // card survives a pause instead of vanishing
                            // instantly: it only actually hides once the
                            // control center is closed AND nothing's
                            // played for ~45s. Fully hidden (not a
                            // placeholder) once that happens, so
                            // ccMediaSectionHeight collapses to 0 and the
                            // sliders below just slide up to meet the
                            // divider under the tiles.
                            Item {
                                id: mediaSection
                                anchors.top: tileDivider.bottom
                                anchors.topMargin: pill.ccMediaVisible ? pill.ccPadding / 2 : 0
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: pill.ccPadding
                                anchors.rightMargin: pill.ccPadding
                                height: pill.ccMediaVisible ? pill.ccMediaCardHeight : 0
                                clip: true
                                visible: pill.ccMediaVisible

                                Rectangle {
                                    id: mediaCard
                                    anchors.fill: parent
                                    radius: 18
                                    color: Colors.surfaceContainer
                                    border.width: 1
                                    border.color: Colors.border
                                    clip: true

                                    // Blurred album art background. The
                                    // source Image stays invisible — only
                                    // the MultiEffect (QtQuick.Effects,
                                    // already imported at the top of this
                                    // file) actually paints, same
                                    // hidden-source-plus-effect pattern
                                    // Qt's own MultiEffect docs use.
                                    Image {
                                        id: mediaArtBg
                                        anchors.fill: parent
                                        source: pill.ccMediaPlayer?.trackArtUrl ?? ""
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        smooth: true
                                        cache: false
                                        visible: false
                                    }

                                    MultiEffect {
                                        anchors.fill: parent
                                        source: mediaArtBg
                                        visible: mediaArtBg.status === Image.Ready
                                        blurEnabled: true
                                        blur: 1.0
                                        blurMax: 64
                                        saturation: 0.1
                                    }

                                    // Plain dark fill as a fallback
                                    // background when the player reports
                                    // no art at all, so the card doesn't
                                    // show the layer's transparent/garbage
                                    // pixels underneath.
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: parent.radius
                                        color: Colors.surfaceContainerLowest
                                        visible: !mediaArtBg.visible && mediaArtBg.status !== Image.Ready
                                    }

                                    // Dark scrim over the blurred art so
                                    // the white foreground text/icons stay
                                    // readable regardless of the art's own
                                    // colors.
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: parent.radius
                                        color: Colors.surfaceContainerLowest
                                        opacity: 0.55
                                    }

                                    Item {
                                        id: mediaContent
                                        anchors.fill: parent
                                        anchors.margins: 16

                                        Column {
                                            id: mediaTitleCol
                                            anchors.top: parent.top
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            spacing: 3

                                            Text {
                                                width: parent.width
                                                text: root.cleanMediaText(pill.ccMediaPlayer?.trackTitle ?? "")
                                                color: "#ffffff"
                                                font.pixelSize: 16
                                                font.weight: Font.DemiBold
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                width: parent.width
                                                text: root.cleanMediaText(pill.ccMediaPlayer?.trackArtist ?? "")
                                                color: Colors.text
                                                font.pixelSize: 12
                                                elide: Text.ElideRight
                                            }
                                        }

                                        // Transport row — prev / big
                                        // play-pause / next. Hand-drawn
                                        // Canvas glyphs, same "no icon
                                        // fonts" rule the rest of the
                                        // file's icons follow, with a
                                        // hover-brightened circular
                                        // background on each.
                                        Row {
                                            id: mediaTransportRow
                                            anchors.top: mediaTitleCol.bottom
                                            anchors.topMargin: 12
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            spacing: 22

                                            Item {
                                                id: prevBtn
                                                width: 40
                                                height: 40
                                                readonly property bool canGo: pill.ccMediaPlayer?.canGoPrevious ?? false

                                                Rectangle {
                                                    anchors.fill: parent
                                                    radius: width / 2
                                                    color: "#ffffff"
                                                    opacity: prevArea.containsMouse && prevBtn.canGo ? 0.16 : 0
                                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                                }

                                                Canvas {
                                                    anchors.centerIn: parent
                                                    width: 18
                                                    height: 16
                                                    opacity: prevBtn.canGo ? 1 : 0.35
                                                    onPaint: {
                                                        const ctx = getContext("2d");
                                                        ctx.reset();
                                                        ctx.fillStyle = "#ffffff";
                                                        ctx.beginPath();
                                                        ctx.moveTo(16, 1);
                                                        ctx.lineTo(6, 8);
                                                        ctx.lineTo(16, 15);
                                                        ctx.closePath();
                                                        ctx.fill();
                                                        ctx.fillRect(2, 1, 2.4, 14);
                                                    }
                                                }

                                                MouseArea {
                                                    id: prevArea
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    enabled: prevBtn.canGo
                                                    onClicked: pill.ccMediaPlayer.previous()
                                                }
                                            }

                                            Item {
                                                id: playPauseBtn
                                                width: 58
                                                height: 58
                                                readonly property bool canToggle: pill.ccMediaPlayer?.canTogglePlaying ?? false
                                                readonly property bool isPlaying: pill.ccMediaPlayer?.isPlaying ?? false

                                                Rectangle {
                                                    anchors.fill: parent
                                                    radius: width / 2
                                                    color: Colors.accent
                                                    opacity: playPauseArea.containsMouse ? 0.92 : 1
                                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                                }

                                                Canvas {
                                                    id: playPauseIcon
                                                    anchors.centerIn: parent
                                                    width: 20
                                                    height: 20
                                                    readonly property bool playing: playPauseBtn.isPlaying

                                                    onPlayingChanged: requestPaint()
                                                    Component.onCompleted: requestPaint()

                                                    onPaint: {
                                                        const ctx = getContext("2d");
                                                        ctx.reset();
                                                        ctx.fillStyle = Colors.background;
                                                        if (playing) {
                                                            ctx.fillRect(3, 1, 5.5, 18);
                                                            ctx.fillRect(11.5, 1, 5.5, 18);
                                                        } else {
                                                            ctx.beginPath();
                                                            ctx.moveTo(3, 1);
                                                            ctx.lineTo(18, 10);
                                                            ctx.lineTo(3, 19);
                                                            ctx.closePath();
                                                            ctx.fill();
                                                        }
                                                    }
                                                }

                                                MouseArea {
                                                    id: playPauseArea
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    enabled: playPauseBtn.canToggle
                                                    onClicked: pill.ccMediaPlayer.togglePlaying()
                                                }
                                            }

                                            Item {
                                                id: nextBtn
                                                width: 40
                                                height: 40
                                                readonly property bool canGo: pill.ccMediaPlayer?.canGoNext ?? false

                                                Rectangle {
                                                    anchors.fill: parent
                                                    radius: width / 2
                                                    color: "#ffffff"
                                                    opacity: nextArea.containsMouse && nextBtn.canGo ? 0.16 : 0
                                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                                }

                                                Canvas {
                                                    anchors.centerIn: parent
                                                    width: 18
                                                    height: 16
                                                    opacity: nextBtn.canGo ? 1 : 0.35
                                                    onPaint: {
                                                        const ctx = getContext("2d");
                                                        ctx.reset();
                                                        ctx.fillStyle = "#ffffff";
                                                        ctx.beginPath();
                                                        ctx.moveTo(2, 1);
                                                        ctx.lineTo(12, 8);
                                                        ctx.lineTo(2, 15);
                                                        ctx.closePath();
                                                        ctx.fill();
                                                        ctx.fillRect(13.6, 1, 2.4, 14);
                                                    }
                                                }

                                                MouseArea {
                                                    id: nextArea
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    enabled: nextBtn.canGo
                                                    onClicked: pill.ccMediaPlayer.next()
                                                }
                                            }
                                        }

                                        // Progress bar — position/length
                                        // are plain seconds from MPRIS.
                                        // pill.mediaPosition is the polled
                                        // live value (see the Timer up in
                                        // pill's property block); dragging
                                        // writes straight to
                                        // activePlayer.position, same
                                        // click/drag-to-set pattern as the
                                        // volume/brightness sliders above.
                                        Item {
                                            id: mediaProgress
                                            anchors.top: mediaTransportRow.bottom
                                            anchors.topMargin: 14
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            height: 34

                                            readonly property real length: pill.ccMediaPlayer?.length ?? 0
                                            readonly property real pos: Math.min(pill.mediaPosition, mediaProgress.length)
                                            readonly property real fillFrac: mediaProgress.length > 0
                                                ? Math.max(0, Math.min(1, mediaProgress.pos / mediaProgress.length))
                                                : 0
                                            readonly property bool seekable: pill.ccMediaPlayer?.canSeek ?? false

                                            Item {
                                                id: progressTrackArea
                                                anchors.top: parent.top
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                height: 14

                                                Rectangle {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: parent.width
                                                    height: 6
                                                    radius: 3
                                                    color: "#ffffff"
                                                    opacity: 0.18
                                                }

                                                Rectangle {
                                                    anchors.left: parent.left
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    height: 6
                                                    radius: 3
                                                    color: Colors.accent
                                                    width: parent.width * mediaProgress.fillFrac

                                                    Behavior on width {
                                                        enabled: !progressDrag.pressed
                                                        NumberAnimation { duration: 200 }
                                                    }
                                                }

                                                Rectangle {
                                                    readonly property real size: progressDrag.containsMouse || progressDrag.pressed ? 16 : 12
                                                    width: size
                                                    height: size
                                                    radius: size / 2
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    x: Math.max(0, Math.min(parent.width - size, parent.width * mediaProgress.fillFrac - size / 2))
                                                    color: "#ffffff"
                                                    visible: mediaProgress.seekable

                                                    Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                                    Behavior on height { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                                    Behavior on x {
                                                        enabled: !progressDrag.pressed
                                                        NumberAnimation { duration: 100 }
                                                    }
                                                }

                                                MouseArea {
                                                    id: progressDrag
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    enabled: mediaProgress.seekable && mediaProgress.length > 0
                                                    function setFromX(x) {
                                                        const frac = Math.max(0, Math.min(1, x / width));
                                                        const newPos = frac * mediaProgress.length;
                                                        pill.ccMediaPlayer.position = newPos;
                                                        pill.mediaPosition = newPos;
                                                    }
                                                    onPressed: (mouse) => setFromX(mouse.x)
                                                    onPositionChanged: (mouse) => { if (pressed) setFromX(mouse.x); }
                                                }
                                            }

                                            Text {
                                                anchors.top: progressTrackArea.bottom
                                                anchors.topMargin: 3
                                                anchors.left: parent.left
                                                text: root.formatMediaTime(mediaProgress.pos)
                                                color: Colors.textSecondary
                                                font.pixelSize: 10
                                            }

                                            Text {
                                                anchors.top: progressTrackArea.bottom
                                                anchors.topMargin: 3
                                                anchors.right: parent.right
                                                text: root.formatMediaTime(mediaProgress.length)
                                                color: Colors.textSecondary
                                                font.pixelSize: 10
                                            }
                                        }

                                        // Output device label — same
                                        // Pipewire.defaultAudioSink the
                                        // volume slider below reads, so
                                        // this always names whatever
                                        // device the card's transport
                                        // controls (and that slider) are
                                        // actually acting on.
                                        Row {
                                            anchors.top: mediaProgress.bottom
                                            anchors.topMargin: 6
                                            anchors.left: parent.left
                                            spacing: 6

                                            Canvas {
                                                width: 12
                                                height: 12
                                                anchors.verticalCenter: parent.verticalCenter
                                                onPaint: {
                                                    const ctx = getContext("2d");
                                                    ctx.reset();
                                                    ctx.fillStyle = Colors.textTertiary;
                                                    ctx.beginPath();
                                                    ctx.moveTo(1, 4);
                                                    ctx.lineTo(4, 4);
                                                    ctx.lineTo(8, 1);
                                                    ctx.lineTo(8, 11);
                                                    ctx.lineTo(4, 8);
                                                    ctx.lineTo(1, 8);
                                                    ctx.closePath();
                                                    ctx.fill();
                                                    ctx.strokeStyle = Colors.textTertiary;
                                                    ctx.lineWidth = 1;
                                                    ctx.beginPath();
                                                    ctx.arc(9, 6, 3, -0.7, 0.7);
                                                    ctx.stroke();
                                                }
                                            }

                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: pill.sink?.description || pill.sink?.nickname || pill.sink?.name || "No output device"
                                                color: Colors.textTertiary
                                                font.pixelSize: 10
                                                elide: Text.ElideRight
                                                width: Math.min(implicitWidth, mediaContent.width - 20)
                                            }
                                        }
                                    }
                                }
                            }

                            // Trailing divider for the media section,
                            // same hairline as tileDivider/sliderDivider —
                            // collapses to nothing when the card itself is
                            // hidden so no orphan line is left behind.
                            Rectangle {
                                id: mediaDivider
                                anchors.top: mediaSection.bottom
                                anchors.topMargin: pill.ccMediaVisible ? pill.ccPadding / 2 : 0
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: pill.ccPadding
                                anchors.rightMargin: pill.ccPadding
                                height: pill.ccMediaVisible ? pill.ccDividerHeight : 0
                                color: Colors.borderHover
                                opacity: 0.5
                                visible: pill.ccMediaVisible
                            }

                            Text {
                                id: quickSettingsLabel
                                anchors.top: mediaDivider.bottom
                                anchors.topMargin: pill.ccPadding / 2
                                anchors.left: parent.left
                                anchors.leftMargin: pill.ccPadding
                                text: "QUICK SETTINGS"
                                color: Colors.textDisabled
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                                font.letterSpacing: 0.6
                            }

                            // Volume slider — bound directly to the same
                            // Pipewire default sink the volume OSD and the
                            // audio tile use, drawn with the exact thick
                            // rounded-bar style the audio sub-view's
                            // per-device sliders use.
                            Item {
                                id: volumeSection
                                anchors.top: quickSettingsLabel.bottom
                                anchors.topMargin: pill.ccSectionLabelGap
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: pill.ccPadding
                                anchors.rightMargin: pill.ccPadding
                                height: pill.ccSliderRowHeight

                                readonly property real vol: pill.sink?.audio.volume ?? 0
                                readonly property bool muted: pill.sink?.audio.muted ?? false

                                Text {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    text: "Volume"
                                    color: Colors.text
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                }

                                Text {
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    text: volumeSection.muted ? "Muted" : Math.round(volumeSection.vol * 100) + "%"
                                    color: Colors.textTertiary
                                    font.pixelSize: 12
                                }

                                Item {
                                    id: volTrackArea
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: 20

                                    readonly property real fillFrac: Math.max(0, Math.min(1, volumeSection.muted ? 0 : volumeSection.vol))

                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width
                                        height: 14
                                        radius: 7
                                        color: Colors.surfaceContainer
                                        border.width: 1
                                        border.color: volDrag.containsMouse || volDrag.pressed ? Colors.borderHover : Colors.border

                                        Behavior on border.color { ColorAnimation { duration: 150 } }
                                    }

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        height: 14
                                        radius: 7
                                        color: Colors.accent
                                        width: parent.width * volTrackArea.fillFrac

                                        Behavior on width {
                                            enabled: !volDrag.pressed
                                            NumberAnimation { duration: 100 }
                                        }
                                    }

                                    Rectangle {
                                        id: volThumb
                                        readonly property real size: volDrag.containsMouse || volDrag.pressed ? 20 : 18
                                        width: size
                                        height: size
                                        radius: size / 2
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: Math.max(0, Math.min(parent.width - size, parent.width * volTrackArea.fillFrac - size / 2))
                                        color: "#ffffff"
                                        border.width: 2
                                        border.color: Colors.accent

                                        Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                        Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                        Behavior on x {
                                            enabled: !volDrag.pressed
                                            NumberAnimation { duration: 100 }
                                        }
                                    }

                                    MouseArea {
                                        id: volDrag
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        function setFromX(x) {
                                            if (pill.sink) pill.sink.audio.volume = Math.max(0, Math.min(1, x / width));
                                        }
                                        onPressed: (mouse) => setFromX(mouse.x)
                                        onPositionChanged: (mouse) => { if (pressed) setFromX(mouse.x); }
                                    }
                                }
                            }

                            // Brightness slider — no native Quickshell
                            // service for this, so it shells out to
                            // brightnessctl (see pill.brightnessPct/
                            // setBrightness above), same pragmatic
                            // approach as bluetooth/night light. Otherwise
                            // an exact copy of the volume slider above.
                            Item {
                                id: brightnessSection
                                anchors.top: volumeSection.bottom
                                anchors.topMargin: pill.ccPadding
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: pill.ccPadding
                                anchors.rightMargin: pill.ccPadding
                                height: pill.ccSliderRowHeight

                                Text {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    text: "Brightness"
                                    color: Colors.text
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                }

                                Text {
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    text: Math.round(pill.brightnessPct * 100) + "%"
                                    color: Colors.textTertiary
                                    font.pixelSize: 12
                                }

                                Item {
                                    id: brightTrackArea
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: 20

                                    readonly property real fillFrac: Math.max(0, Math.min(1, pill.brightnessPct))

                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width
                                        height: 14
                                        radius: 7
                                        color: Colors.surfaceContainer
                                        border.width: 1
                                        border.color: brightDrag.containsMouse || brightDrag.pressed ? Colors.warningContainer : Colors.border

                                        Behavior on border.color { ColorAnimation { duration: 150 } }
                                    }

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        height: 14
                                        radius: 7
                                        color: Colors.warning
                                        width: parent.width * brightTrackArea.fillFrac

                                        Behavior on width {
                                            enabled: !brightDrag.pressed
                                            NumberAnimation { duration: 100 }
                                        }
                                    }

                                    Rectangle {
                                        id: brightThumb
                                        readonly property real size: brightDrag.containsMouse || brightDrag.pressed ? 20 : 18
                                        width: size
                                        height: size
                                        radius: size / 2
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: Math.max(0, Math.min(parent.width - size, parent.width * brightTrackArea.fillFrac - size / 2))
                                        color: "#ffffff"
                                        border.width: 2
                                        border.color: Colors.warning

                                        Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                        Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                        Behavior on x {
                                            enabled: !brightDrag.pressed
                                            NumberAnimation { duration: 100 }
                                        }
                                    }

                                    MouseArea {
                                        id: brightDrag
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        function setFromX(x) {
                                            pill.setBrightness(x / width);
                                        }
                                        onPressed: (mouse) => setFromX(mouse.x)
                                        onPositionChanged: (mouse) => { if (pressed) setFromX(mouse.x); }
                                    }
                                }
                            }

                            // Same hairline divider as above the sliders,
                            // separating them from the notifications
                            // section below.
                            Rectangle {
                                id: sliderDivider
                                anchors.top: brightnessSection.bottom
                                anchors.topMargin: pill.ccPadding / 2
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: pill.ccPadding
                                anchors.rightMargin: pill.ccPadding
                                height: pill.ccDividerHeight
                                color: Colors.borderHover
                                opacity: 0.5
                            }

                            // Notification history — inline and always
                            // visible here (this IS the control center's
                            // only notifications view now, not a page
                            // behind a toggle), listing every notification
                            // logged so far (Peace mode or not — Peace
                            // only suppresses the popup, never this list)
                            // plus a "clear all" button. Same row/list
                            // styling as before, just relocated.
                            Item {
                                id: historySection
                                anchors.top: sliderDivider.bottom
                                anchors.topMargin: pill.ccPadding / 2
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: pill.ccHistoryLabelHeight
                                    + pill.ccHistoryListHeight
                                    + pill.ccHistoryFooterHeight

                                Text {
                                    id: historyLabel
                                    anchors.top: parent.top
                                    anchors.left: parent.left
                                    anchors.leftMargin: pill.ccPadding
                                    text: "Notifications"
                                    color: Colors.textTertiary
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                }

                                // Distinct empty state, same idea as the
                                // bluetooth page's "no paired devices"
                                // text.
                                Text {
                                    anchors.top: historyLabel.bottom
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.topMargin: (historySection.height - pill.ccHistoryLabelHeight - pill.ccHistoryFooterHeight) / 2 - 8
                                    visible: pill.notifHistory.length === 0
                                    text: "No notifications"
                                    color: Colors.textDisabled
                                    font.pixelSize: 12
                                }

                                ListView {
                                    id: historyList
                                    anchors.top: historyLabel.bottom
                                    anchors.topMargin: 4
                                    width: parent.width
                                    height: pill.ccHistoryListHeight
                                    spacing: pill.ccHistoryRowSpacing
                                    visible: pill.notifHistory.length > 0
                                    clip: true
                                    model: pill.notifHistory

                                    delegate: Item {
                                        id: histRow
                                        required property var modelData
                                        width: ListView.view.width
                                        height: pill.ccHistoryRowHeight

                                        readonly property string iconSource: pill.resolveIcon(histRow.modelData.appIcon)

                                        // Hover highlight — makes the row under
                                        // the cursor visually obvious before a
                                        // click-to-open or remove. Same
                                        // always-live HoverHandler + gated-read
                                        // idea used elsewhere in this file,
                                        // just simpler here since there's no
                                        // enabled-toggling to fight.
                                        HoverHandler {
                                            id: histRowHover
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 10
                                            color: Colors.text
                                            opacity: histRowHover.hovered ? 0.06 : 0

                                            Behavior on opacity {
                                                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                                            }
                                        }

                                        // Whole-row click invokes the notification's
                                        // "default" action if it has one (freedesktop's
                                        // click-a-notification convention) — a no-op for
                                        // plain notify-send entries with no actions at
                                        // all. The remove button below is a later
                                        // sibling covering its own small area, so it
                                        // paints on top and wins hit-testing there,
                                        // same split-action pattern the control
                                        // center's tiles use — this MouseArea never
                                        // sees that click.
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: pill.activateNotifHistoryEntry(histRow.modelData)
                                        }

                                        Row {
                                            anchors.fill: parent
                                            anchors.leftMargin: 18
                                            anchors.rightMargin: 42
                                            spacing: 12

                                            Item {
                                                width: 24
                                                height: 24
                                                anchors.verticalCenter: parent.verticalCenter

                                                IconImage {
                                                    id: histIcon
                                                    anchors.fill: parent
                                                    implicitSize: 24
                                                    visible: histRow.iconSource.length > 0
                                                    source: histRow.iconSource
                                                }

                                                Rectangle {
                                                    anchors.fill: parent
                                                    radius: width / 2
                                                    visible: !histIcon.visible
                                                    color: pill.notifAvatarColor(histRow.modelData.appName)

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: histRow.modelData.appName.charAt(0).toUpperCase()
                                                        color: "#ffffff"
                                                        font.pixelSize: 11
                                                        font.weight: Font.DemiBold
                                                    }
                                                }
                                            }

                                            Column {
                                                width: parent.width - 34
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: 1

                                                Text {
                                                    width: parent.width
                                                    text: histRow.modelData.summary || histRow.modelData.appName
                                                    color: histRow.modelData.critical ? Colors.critical : Colors.text
                                                    font.pixelSize: 12
                                                    font.weight: Font.Medium
                                                    elide: Text.ElideRight
                                                }

                                                Text {
                                                    width: parent.width
                                                    visible: histRow.modelData.body.length > 0
                                                    text: histRow.modelData.body
                                                    color: Colors.textTertiary
                                                    font.pixelSize: 11
                                                    elide: Text.ElideRight
                                                }
                                            }
                                        }

                                        // Remove ("X") — small, unobtrusive, pinned to
                                        // the row's right edge. Declared after the Row
                                        // above so it's the topmost thing under the
                                        // cursor within its own bounds, keeping its
                                        // click fully separate from the row-wide
                                        // MouseArea's click-to-open above.
                                        Item {
                                            width: 20
                                            height: 20
                                            anchors.right: parent.right
                                            anchors.rightMargin: 12
                                            anchors.verticalCenter: parent.verticalCenter

                                            Canvas {
                                                anchors.fill: parent
                                                onPaint: {
                                                    const ctx = getContext("2d");
                                                    ctx.reset();
                                                    ctx.strokeStyle = Colors.textDisabled;
                                                    ctx.lineWidth = 1.4;
                                                    ctx.lineCap = "round";
                                                    ctx.beginPath();
                                                    ctx.moveTo(6, 6);
                                                    ctx.lineTo(14, 14);
                                                    ctx.moveTo(14, 6);
                                                    ctx.lineTo(6, 14);
                                                    ctx.stroke();
                                                }
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: pill.removeNotifHistoryEntry(histRow.modelData.id)
                                            }
                                        }
                                    }
                                }

                                // "Clear all" — pinned to the section's
                                // own bottom edge via ccHistoryFooterHeight,
                                // same fixed-strip idea ccSubHeaderHeight
                                // uses at the top of the sub-pages.
                                Item {
                                    anchors.top: historyList.bottom
                                    width: parent.width
                                    height: pill.ccHistoryFooterHeight

                                    Text {
                                        anchors.centerIn: parent
                                        text: "Clear all"
                                        color: pill.notifHistory.length > 0 ? Colors.accent : Colors.iconMuted
                                        font.pixelSize: 12
                                        font.weight: Font.Medium
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: pill.notifHistory.length > 0
                                        onClicked: pill.clearNotifHistory()
                                    }
                                }
                            }
                        }

                        // PAGE 1 — wifi networks.
                        Item {
                            width: pill.ccWidth
                            height: pill.ccWifiHeight

                            Item {
                                id: wifiHeader
                                width: parent.width
                                height: pill.ccSubHeaderHeight

                                Item {
                                    width: 32
                                    height: parent.height
                                    anchors.left: parent.left

                                    Canvas {
                                        anchors.centerIn: parent
                                        width: 16
                                        height: 16
                                        onPaint: {
                                            const ctx = getContext("2d");
                                            ctx.reset();
                                            ctx.strokeStyle = Colors.text;
                                            ctx.lineWidth = 1.8;
                                            ctx.lineCap = "round";
                                            ctx.lineJoin = "round";
                                            ctx.beginPath();
                                            ctx.moveTo(10, 3);
                                            ctx.lineTo(5, 8);
                                            ctx.lineTo(10, 13);
                                            ctx.stroke();
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: pill.ccView = "tiles"
                                    }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: "Wifi"
                                    color: Colors.text
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                }
                            }

                            ListView {
                                anchors.top: wifiHeader.bottom
                                width: parent.width
                                height: pill.ccWifiHeight - pill.ccSubHeaderHeight
                                clip: true
                                model: pill.wifiDevice
                                    ? [...pill.wifiDevice.networks.values].sort((a, b) => b.signalStrength - a.signalStrength)
                                    : []

                                delegate: Item {
                                    id: netRow
                                    required property var modelData
                                    width: ListView.view.width
                                    height: pill.ccWifiRowHeight

                                    readonly property int level: netRow.modelData.signalStrength <= 0 ? 0
                                        : netRow.modelData.signalStrength < 40 ? 1
                                        : netRow.modelData.signalStrength < 70 ? 2 : 3

                                    Row {
                                        anchors.fill: parent
                                        anchors.leftMargin: 16
                                        anchors.rightMargin: 16
                                        spacing: 10

                                        // Mini signal bars for THIS
                                        // network's own strength — a
                                        // lighter-weight indicator than
                                        // reusing the full NetworkGlyph
                                        // component (which only ever
                                        // reflects the connected network).
                                        Row {
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 2

                                            Repeater {
                                                model: 3

                                                delegate: Rectangle {
                                                    required property int index
                                                    width: 3
                                                    height: 5 + index * 4
                                                    anchors.bottom: parent.bottom
                                                    radius: 1
                                                    color: netRow.level > index ? Colors.text : Colors.borderHover
                                                }
                                            }
                                        }

                                        Text {
                                            width: parent.width - 40
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: netRow.modelData.name
                                            color: netRow.modelData.connected ? Colors.accent : Colors.text
                                            font.pixelSize: 13
                                            font.weight: netRow.modelData.connected ? Font.DemiBold : Font.Normal
                                            elide: Text.ElideRight
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        // Only known (previously-connected)
                                        // networks connect with a single
                                        // tap — a brand-new secured network
                                        // needs a PSK prompt that isn't
                                        // built yet, the same "pairing new
                                        // devices not implemented" limit
                                        // the spec calls out for bluetooth.
                                        enabled: netRow.modelData.known && !netRow.modelData.connected
                                        onClicked: netRow.modelData.connect()
                                    }
                                }
                            }
                        }

                        // PAGE 2 — audio output devices.
                        Item {
                            width: pill.ccWidth
                            height: pill.ccAudioHeight

                            Item {
                                id: audioHeader
                                width: parent.width
                                height: pill.ccSubHeaderHeight

                                Item {
                                    width: 32
                                    height: parent.height
                                    anchors.left: parent.left

                                    Canvas {
                                        anchors.centerIn: parent
                                        width: 16
                                        height: 16
                                        onPaint: {
                                            const ctx = getContext("2d");
                                            ctx.reset();
                                            ctx.strokeStyle = Colors.text;
                                            ctx.lineWidth = 1.8;
                                            ctx.lineCap = "round";
                                            ctx.lineJoin = "round";
                                            ctx.beginPath();
                                            ctx.moveTo(10, 3);
                                            ctx.lineTo(5, 8);
                                            ctx.lineTo(10, 13);
                                            ctx.stroke();
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: pill.ccView = "tiles"
                                    }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: "Audio Output"
                                    color: Colors.text
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                }
                            }

                            ListView {
                                anchors.top: audioHeader.bottom
                                width: parent.width
                                height: pill.ccAudioHeight - pill.ccSubHeaderHeight
                                clip: true
                                model: pill.audioSinks

                                delegate: Item {
                                    id: sinkRow
                                    required property var modelData
                                    width: ListView.view.width
                                    height: pill.ccAudioRowHeight

                                    readonly property bool isDefault: pill.sink && modelData.id === pill.sink.id

                                    Column {
                                        anchors.fill: parent
                                        anchors.leftMargin: 16
                                        anchors.rightMargin: 16
                                        anchors.topMargin: 6
                                        spacing: 6

                                        // Name row — tapping it (outside
                                        // the slider strip below) makes
                                        // this device the system default.
                                        Item {
                                            width: parent.width
                                            height: 16

                                            Row {
                                                anchors.fill: parent
                                                spacing: 8

                                                Rectangle {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 7
                                                    height: 7
                                                    radius: 3.5
                                                    color: sinkRow.isDefault ? Colors.accent : "transparent"
                                                    border.color: Colors.iconMuted
                                                    border.width: sinkRow.isDefault ? 0 : 1
                                                }

                                                Text {
                                                    width: parent.width - 15
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: sinkRow.modelData.description || sinkRow.modelData.nickname || sinkRow.modelData.name
                                                    color: sinkRow.isDefault ? Colors.text : Colors.textTertiary
                                                    font.pixelSize: 12
                                                    font.weight: sinkRow.isDefault ? Font.DemiBold : Font.Normal
                                                    elide: Text.ElideRight
                                                }
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: Pipewire.preferredDefaultAudioSink = sinkRow.modelData
                                            }
                                        }

                                        // Thick, rounded, drag-to-set
                                        // per-device volume slider.
                                        Item {
                                            id: volSlider
                                            width: parent.width
                                            height: 14

                                            readonly property real vol: sinkRow.modelData.audio.volume

                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width
                                                height: 10
                                                radius: 5
                                                color: Colors.border
                                            }

                                            Rectangle {
                                                anchors.left: parent.left
                                                anchors.verticalCenter: parent.verticalCenter
                                                height: 10
                                                radius: 5
                                                color: Colors.accent
                                                width: parent.width * Math.max(0, Math.min(1, volSlider.vol))

                                                Behavior on width {
                                                    enabled: !volDrag.pressed
                                                    NumberAnimation { duration: 100 }
                                                }
                                            }

                                            MouseArea {
                                                id: volDrag
                                                anchors.fill: parent
                                                function setFromX(x) {
                                                    sinkRow.modelData.audio.volume = Math.max(0, Math.min(1, x / width));
                                                }
                                                onPressed: (mouse) => setFromX(mouse.x)
                                                onPositionChanged: (mouse) => { if (pressed) setFromX(mouse.x); }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // PAGE 3 — bluetooth paired devices.
                        Item {
                            width: pill.ccWidth
                            height: pill.ccBluetoothHeight

                            Item {
                                id: bluetoothHeader
                                width: parent.width
                                height: pill.ccSubHeaderHeight

                                Item {
                                    width: 32
                                    height: parent.height
                                    anchors.left: parent.left

                                    Canvas {
                                        anchors.centerIn: parent
                                        width: 16
                                        height: 16
                                        onPaint: {
                                            const ctx = getContext("2d");
                                            ctx.reset();
                                            ctx.strokeStyle = Colors.text;
                                            ctx.lineWidth = 1.8;
                                            ctx.lineCap = "round";
                                            ctx.lineJoin = "round";
                                            ctx.beginPath();
                                            ctx.moveTo(10, 3);
                                            ctx.lineTo(5, 8);
                                            ctx.lineTo(10, 13);
                                            ctx.stroke();
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: pill.ccView = "tiles"
                                    }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: "Bluetooth"
                                    color: Colors.text
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                }
                            }

                            // Powered-off placeholder — the spec calls
                            // out handling this gracefully rather than
                            // just showing an empty/broken list when the
                            // radio itself is off.
                            Text {
                                anchors.top: bluetoothHeader.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.topMargin: (pill.ccBluetoothHeight - pill.ccSubHeaderHeight) / 2 - 8
                                visible: !pill.bluetoothPowered
                                text: "Bluetooth is off"
                                color: Colors.textDisabled
                                font.pixelSize: 12
                            }

                            ListView {
                                anchors.top: bluetoothHeader.bottom
                                width: parent.width
                                height: pill.ccBluetoothHeight - pill.ccSubHeaderHeight
                                visible: pill.bluetoothPowered
                                clip: true
                                model: pill.bluetoothDevices

                                // Distinct from the powered-off placeholder
                                // above — bluetooth is on, there's just
                                // nothing paired yet.
                                Text {
                                    anchors.centerIn: parent
                                    visible: pill.bluetoothDevices.length === 0
                                    text: "No paired devices"
                                    color: Colors.textDisabled
                                    font.pixelSize: 12
                                }

                                delegate: Item {
                                    id: btRow
                                    required property var modelData
                                    width: ListView.view.width
                                    height: pill.ccBluetoothRowHeight

                                    Row {
                                        anchors.fill: parent
                                        anchors.leftMargin: 16
                                        anchors.rightMargin: 16
                                        spacing: 10

                                        // Connected-status dot — filled
                                        // green when connected, hollow
                                        // outline otherwise. Same visual
                                        // language as the audio page's
                                        // "is this the default sink" dot.
                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 7
                                            height: 7
                                            radius: 3.5
                                            color: btRow.modelData.connected ? Colors.success : "transparent"
                                            border.color: Colors.iconMuted
                                            border.width: btRow.modelData.connected ? 0 : 1
                                        }

                                        Text {
                                            width: parent.width - 17
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: btRow.modelData.name
                                            color: btRow.modelData.connected ? Colors.accent : Colors.text
                                            font.pixelSize: 13
                                            font.weight: btRow.modelData.connected ? Font.DemiBold : Font.Normal
                                            elide: Text.ElideRight
                                        }
                                    }

                                    // Tap a device: connect if
                                    // disconnected, disconnect if
                                    // connected — one action per tap,
                                    // matching the tile split-tap spec's
                                    // "tapping toggles" phrasing for a
                                    // list row that only has one action.
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: pill.toggleBluetoothDeviceConnection(btRow.modelData)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // POWER MENU (Ctrl+Alt+Delete) — same morph pattern as the
            // launcher/control center: the pill grows into a flat row of
            // five tiles. Safe actions (Lock, Suspend) fire on the first
            // tap; the destructive ones (Log out, Reboot, Power off) arm
            // on the first tap via pill.tapDestructive() (tile goes red,
            // label flips to "Confirm") and only fire on a second tap
            // within pmArmTimer's window — see that function's comment
            // for the disarm/re-arm behavior.
            Item {
                id: powerMenu
                anchors.fill: parent
                visible: opacity > 0
                opacity: pill.powerMenuOpen ? 1 : 0

                // Same 250ms/easing as every other pill-content crossfade
                // above, so this lands in step with the container's
                // width/height Behavior.
                Behavior on opacity {
                    NumberAnimation {
                        duration: 250
                        easing.type: Easing.OutCubic
                    }
                }

                // Invisible focus target so Escape works from anywhere in
                // this surface — same idea as ccKeyCatcher above, this
                // page has no text field to anchor focus to either.
                Item {
                    id: pmKeyCatcher
                    anchors.fill: parent
                    Keys.onEscapePressed: pill.closePowerMenu()
                }

                Row {
                    anchors.centerIn: parent
                    spacing: pill.pmTileSpacing

                    // LOCK — safe, fires immediately.
                    Item {
                        width: pill.pmTileSize
                        height: pill.pmTileSize

                        Rectangle {
                            anchors.fill: parent
                            radius: 16
                            color: Colors.surfaceContainer
                            border.color: Colors.border
                            border.width: 1
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: pill.lockSession()
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: 6

                            LockGlyph { anchors.horizontalCenter: parent.horizontalCenter }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "Lock"
                                color: Colors.text
                                font.pixelSize: 11
                                font.weight: Font.Medium
                            }
                        }
                    }

                    // SUSPEND — safe, fires immediately.
                    Item {
                        width: pill.pmTileSize
                        height: pill.pmTileSize

                        Rectangle {
                            anchors.fill: parent
                            radius: 16
                            color: Colors.surfaceContainer
                            border.color: Colors.border
                            border.width: 1
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: pill.suspendSession()
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: 6

                            SuspendGlyph { anchors.horizontalCenter: parent.horizontalCenter }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "Suspend"
                                color: Colors.text
                                font.pixelSize: 11
                                font.weight: Font.Medium
                            }
                        }
                    }

                    // LOG OUT — destructive: two-step confirm.
                    Item {
                        id: logoutTile
                        width: pill.pmTileSize
                        height: pill.pmTileSize
                        readonly property bool armed: pill.armedPmAction === "logout"

                        Rectangle {
                            anchors.fill: parent
                            radius: 16
                            color: logoutTile.armed ? Colors.criticalContainer : Colors.surfaceContainer
                            border.color: logoutTile.armed ? Colors.critical : Colors.border
                            border.width: 1

                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: pill.tapDestructive("logout")
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: 6

                            LogoutGlyph { anchors.horizontalCenter: parent.horizontalCenter }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: logoutTile.armed ? "Confirm" : "Log out"
                                color: logoutTile.armed ? Colors.critical : Colors.text
                                font.pixelSize: 11
                                font.weight: Font.Medium
                            }
                        }
                    }

                    // REBOOT — destructive: two-step confirm.
                    Item {
                        id: rebootTile
                        width: pill.pmTileSize
                        height: pill.pmTileSize
                        readonly property bool armed: pill.armedPmAction === "reboot"

                        Rectangle {
                            anchors.fill: parent
                            radius: 16
                            color: rebootTile.armed ? Colors.criticalContainer : Colors.surfaceContainer
                            border.color: rebootTile.armed ? Colors.critical : Colors.border
                            border.width: 1

                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: pill.tapDestructive("reboot")
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: 6

                            RebootGlyph { anchors.horizontalCenter: parent.horizontalCenter }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: rebootTile.armed ? "Confirm" : "Reboot"
                                color: rebootTile.armed ? Colors.critical : Colors.text
                                font.pixelSize: 11
                                font.weight: Font.Medium
                            }
                        }
                    }

                    // POWER OFF — destructive: two-step confirm.
                    Item {
                        id: poweroffTile
                        width: pill.pmTileSize
                        height: pill.pmTileSize
                        readonly property bool armed: pill.armedPmAction === "poweroff"

                        Rectangle {
                            anchors.fill: parent
                            radius: 16
                            color: poweroffTile.armed ? Colors.criticalContainer : Colors.surfaceContainer
                            border.color: poweroffTile.armed ? Colors.critical : Colors.border
                            border.width: 1

                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: pill.tapDestructive("poweroff")
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: 6

                            PowerGlyph { anchors.horizontalCenter: parent.horizontalCenter }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: poweroffTile.armed ? "Confirm" : "Power off"
                                color: poweroffTile.armed ? Colors.critical : Colors.text
                                font.pixelSize: 11
                                font.weight: Font.Medium
                            }
                        }
                    }
                }
            }
        }
    }

    // Clears any leftover query text and grabs keyboard focus the moment
    // the launcher opens (openLauncher() resets pill.launcherQuery, but
    // that's a one-way binding target — the TextInput's own `text` needs
    // clearing separately since it's the source of that binding).
    Connections {
        target: pill
        function onLauncherOpenChanged() {
            if (pill.launcherOpen) {
                launcherField.text = "";
                launcherField.forceActiveFocus();
            }
        }
        // Same idea for the control center — it has no text field, so its
        // invisible ccKeyCatcher Item is what needs the active focus for
        // Keys.onEscapePressed on it to ever fire.
        function onCcOpenChanged() {
            if (pill.ccOpen) {
                ccKeyCatcher.forceActiveFocus();
            }
        }
        // Same idea again for the power menu — no text field, so its own
        // invisible pmKeyCatcher Item needs the active focus for Escape
        // to reach it.
        function onPowerMenuOpenChanged() {
            if (pill.powerMenuOpen) {
                pmKeyCatcher.forceActiveFocus();
            }
        }
    }
}
