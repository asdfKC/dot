-- hyprland.lua
-- Rebuilt from ~/.config/hyprbak/hyprland.lua
-- Theming/tooling layer (general/decoration/animations, wybar, wofi/rofi,
-- wal/wallust) stripped — being replaced by Quickshell + matugen.

--################
--### ENV VARS ###
--################

hl.env("AQ_DRM_DEVICES", "/dev/dri/card1:/dev/dri/card0")
hl.env("WLR_RENDERER", "pixman")


--################
--### MONITORS ###
--################

hl.monitor({ output = "DP-2",     mode = "2560x1440@144", position = "0x0",    scale = 1 })
hl.monitor({ output = "DP-1", mode = "1920x1080@59.79",   position = "2560x0", scale = 1 })


--################
--### PROGRAMS ###
--################

local terminal    = "kitty"
local fileManager = "nautilus"


--#################
--### AUTOSTART ###
--#################

hl.on("hyprland.start", function()
    hl.exec_cmd("bash -lc 'pgrep -x kded6 >/dev/null || kded6; for i in 1 2 3 4 5; do qdbus6 org.kde.kded6 /kded org.kde.kded6.loadModule statusnotifierwatcher >/dev/null 2>&1 && break; sleep 1; done'")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("systemctl --user restart xdg-desktop-portal-hyprland")
    hl.exec_cmd("hyprctl dispatch workspace $(cat /tmp/hypr_prev_workspace 2>/dev/null || echo 1)")
    hl.exec_cmd("rclone mount gdrive: ~/GoogleDrive --daemon --vfs-cache-mode full --vfs-cache-max-size 2G --dir-cache-time 72h --poll-interval 15s")
    -- hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
    hl.exec_cmd("firefox")
    hl.exec_cmd("prismlauncher")
    hl.exec_cmd("sh -c 'vesktop & zapzap & slack & gmessages &'")
    hl.exec_cmd("missioncenter")
    hl.exec_cmd("amberol")
    hl.exec_cmd("pavucontrol")
    hl.exec_cmd("dex -a")
    hl.exec_cmd("kdeconnect-indicator")
    hl.exec_cmd("hyprpaper")
    hl.exec_cmd("wl-paste --watch cliphist store")
end)


--###################
--### INPUT ###
--###################

hl.config({
    input = {
        kb_layout    = "us",
        follow_mouse = 1,
    },
})


--#####################
--### WORKSPACE MAP ###
--#####################

hl.workspace_rule({ workspace = "1",  monitor = "DP-2" })
hl.workspace_rule({ workspace = "2",  monitor = "DP-2" })
hl.workspace_rule({ workspace = "3",  monitor = "DP-2" })
hl.workspace_rule({ workspace = "4",  monitor = "DP-2" })
hl.workspace_rule({ workspace = "5",  monitor = "DP-2" })
hl.workspace_rule({ workspace = "6",  monitor = "DP-2" })
hl.workspace_rule({ workspace = "7",  monitor = "DP-2" })
hl.workspace_rule({ workspace = "8",  monitor = "DP-1" })
hl.workspace_rule({ workspace = "9",  monitor = "DP-1" })
hl.workspace_rule({ workspace = "10", monitor = "DP-1" })


--###################################
--### APPLICATION WORKSPACE RULES ###
--###################################

-- Main Monitor Apps (DP-2) --
hl.window_rule({ match = { class = "^(firefox)$" },                           workspace = "1" })
hl.window_rule({ match = { class = "^(org.prismlauncher.PrismLauncher)$" },   workspace = "4" })

-- Super+C Communication Apps -> Workspace 3
hl.window_rule({ match = { class = "^(vesktop)$" },         workspace = "3 silent" })
hl.window_rule({ match = { class = "^(zapzap)$" },          workspace = "3 silent" })
hl.window_rule({ match = { class = "^(slack)$" },           workspace = "3 silent" })
hl.window_rule({ match = { class = "^(google-messages)$" }, workspace = "3 silent" })

-- Portable Monitor Apps (DP-1) --
hl.window_rule({ match = { class = "^(missioncenter)$" },            workspace = "8 silent",  monitor = "DP-1", maximize = true })
hl.window_rule({ match = { class = "^(amberol)$" },                  workspace = "9 silent",  monitor = "DP-1" })
hl.window_rule({ match = { class = "^(org.pulseaudio.pavucontrol)$" }, workspace = "10 silent", monitor = "DP-1", tile = true })

-- HyprEmoji
hl.window_rule({ match = { title = "^(HyprEmoji)$" }, float = true })
hl.window_rule({ match = { title = "^(HyprEmoji)$" }, size  = "307 340" })
hl.window_rule({ match = { title = "^(HyprEmoji)$" }, move  = "1412 644" })


--###################
--### KEYBINDINGS ###
--###################

local mainMod = "SUPER"

hl.bind(mainMod .. " + RETURN",  hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + Q",       hl.dsp.window.close())
hl.bind(mainMod .. " + E",       hl.dsp.exec_cmd("thunar"))
hl.bind(mainMod .. " + V",       hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + W",       hl.dsp.exec_cmd("firefox"))
hl.bind(mainMod .. " + ESCAPE",  hl.dsp.exec_cmd("missioncenter"))
hl.bind(mainMod .. " + C",       hl.dsp.exec_cmd("sh -c 'vesktop & zapzap & slack & gmessages &'"))
hl.bind(mainMod .. " + L",       hl.dsp.exec_cmd("~/.config/hypr/scripts/lock.sh"))
hl.bind(mainMod .. " + B",       hl.dsp.exec_cmd("blueman-manager"))
hl.bind(mainMod .. " + R",       hl.dsp.exec_cmd("sh -c 'pkill quickshell; sleep 0.5; quickshell &'"))
-- Tap SUPER alone (no other key) to toggle the app launcher — bound as a
-- release-triggered bind on SUPER_L itself (the standard Hyprland recipe
-- for "just the mod key"), so it doesn't clash with every other
-- SUPER+<key> combo bind above/below, which still fire normally since
-- those consume the key before SUPER is released alone.
hl.bind(mainMod .. " + SUPER_L", hl.dsp.exec_cmd("quickshell ipc call launcher toggle"), { release = true })
hl.bind("ALT + A",              hl.dsp.exec_cmd("quickshell ipc call controlcenter toggle"))
hl.bind("CTRL + ALT + DELETE",  hl.dsp.exec_cmd("quickshell ipc call powermenu toggle"))
hl.bind(mainMod .. " + S",       hl.dsp.exec_cmd("~/.config/hypr/scripts/screenshot_noanim.sh region"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.exec_cmd("~/.config/hypr/scripts/screenshot_noanim.sh region"))
hl.bind("PRINT",                 hl.dsp.exec_cmd("~/.config/hypr/scripts/screenshot_noanim.sh full"))
hl.bind("SHIFT + PRINT",         hl.dsp.exec_cmd("~/.config/hypr/scripts/screenshot_noanim.sh region"))

hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 1%+ -l 1.0"), { repeating = true, locked = true })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 1%-"),        { repeating = true, locked = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { repeating = true, locked = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl set 2%+"),                      { repeating = true, locked = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set 2%-"),                      { repeating = true, locked = true })

for i = 1, 9 do
    hl.bind(mainMod .. " + " .. i,         hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. i, hl.dsp.window.move({ workspace = i }))
end
hl.bind(mainMod .. " + 0",         hl.dsp.focus({ workspace = 10 }))
hl.bind(mainMod .. " + SHIFT + 0", hl.dsp.window.move({ workspace = 10 }))

hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

hl.bind("SUPER + SHIFT + P", hl.dsp.exec_cmd("~/bin/kush_panic.sh"))

-- HyprEmoji

hl.bind("SUPER + period", hl.dsp.exec_cmd("hypremoji"))
