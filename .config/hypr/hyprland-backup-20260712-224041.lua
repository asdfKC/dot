-- hyprland.lua
-- Migrated from ~/.config/hypr/hyprland.conf
-- Sourced files inlined with origin comments:
--   ~/.config/hypremoji/hypremoji.conf

--################
--### ENV VARS ###
--################

hl.env("AQ_DRM_DEVICES", "/dev/dri/card2:/dev/dri/card1")
hl.env("WLR_RENDERER", "pixman")


--################
--### MONITORS ###
--################

hl.monitor({ output = "HDMI-A-1",     mode = "2560x1440@144", position = "0x0",    scale = 1 })
hl.monitor({ output = "DP-1", mode = "1920x1080@59.79",   position = "2560x0", scale = 1 })


--################
--### PROGRAMS ###
--################

local terminal    = "kitty"
local fileManager = "dolphin"
local menu        = "wofi --show drun"


--#################
--### AUTOSTART ###
--#################

hl.on("hyprland.start", function()
    hl.exec_cmd("waybar")
    hl.exec_cmd("bash -lc 'pgrep -x kded6 >/dev/null || kded6; for i in 1 2 3 4 5; do qdbus6 org.kde.kded6 /kded org.kde.kded6.loadModule statusnotifierwatcher >/dev/null 2>&1 && break; sleep 1; done'")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("swaync")
    hl.exec_cmd("systemctl --user restart xdg-desktop-portal-hyprland")
    hl.exec_cmd("hyprctl dispatch workspace $(cat /tmp/hypr_prev_workspace 2>/dev/null || echo 1)")
    hl.exec_cmd("rclone mount gdrive: ~/GoogleDrive --daemon --vfs-cache-mode full --vfs-cache-max-size 2G --dir-cache-time 72h --poll-interval 15s")
    hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
    hl.exec_cmd("firefox")
    hl.exec_cmd("prismlauncher")
    hl.exec_cmd("sh -c 'vesktop & zapzap & slack & gmessages &'")
    hl.exec_cmd("missioncenter")
    hl.exec_cmd("spotify")
    hl.exec_cmd("pavucontrol")
end)


--###################
--### LOOK & FEEL ###
--###################

hl.config({
    general = {
        gaps_in     = 8,
        gaps_out    = 22,
        border_size = 2,
        col = {
            active_border   = "0xffb45aff",
            inactive_border = "0xff2a1a3b",
        },
        layout = "dwindle",
    },
    decoration = {
        rounding = 12,
        shadow = {
            enabled = true,
            range   = 6,
            color   = "rgba(0, 0, 0, 0.6)",
        },
        blur = {
            enabled = true,
            size    = 6,
            passes  = 2,
        },
    },
    animations = {
        enabled = true,
    },
    input = {
        kb_layout    = "us",
        follow_mouse = 1,
    },
})

hl.curve("linear",    { type = "bezier", points = { {0.0, 0.0}, {1.0, 1.0}    } })
hl.curve("smoothOut", { type = "bezier", points = { {0.36, 0.0}, {0.66, -0.56} } })
hl.curve("smoothIn",  { type = "bezier", points = { {0.25, 1.0}, {0.5, 1.0}   } })
hl.curve("overshot",  { type = "bezier", points = { {0.05, 0.9}, {0.1, 1.1}   } })

hl.animation({ leaf = "windows",     enabled = true, speed = 6,  bezier = "overshot",  style = "slide" })
hl.animation({ leaf = "windowsOut",  enabled = true, speed = 5,  bezier = "smoothIn",  style = "popin 82%" })
hl.animation({ leaf = "border",      enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "borderangle", enabled = true, speed = 20, bezier = "linear",    style = "loop" })
hl.animation({ leaf = "fade",        enabled = true, speed = 6,  bezier = "smoothOut" })
hl.animation({ leaf = "layers",      enabled = true, speed = 5,  bezier = "smoothOut", style = "slide" })
hl.animation({ leaf = "workspaces",  enabled = true, speed = 7,  bezier = "overshot",  style = "slidefade 18%" })


--####################
--### WORKSPACE MAP ###
--####################

hl.workspace_rule({ workspace = "1",  monitor = "HDMI-A-1" })
hl.workspace_rule({ workspace = "2",  monitor = "HDMI-A-1" })
hl.workspace_rule({ workspace = "3",  monitor = "HDMI-A-1" })
hl.workspace_rule({ workspace = "4",  monitor = "HDMI-A-1" })
hl.workspace_rule({ workspace = "5",  monitor = "HDMI-A-1" })
hl.workspace_rule({ workspace = "6",  monitor = "HDMI-A-1" })
hl.workspace_rule({ workspace = "7",  monitor = "HDMI-A-1" })
hl.workspace_rule({ workspace = "8",  monitor = "DP-1" })
hl.workspace_rule({ workspace = "9",  monitor = "DP-1" })
hl.workspace_rule({ workspace = "10", monitor = "DP-1" })


--###################################
--### APPLICATION WORKSPACE RULES ###
--###################################

-- Main Monitor Apps (HDMI-A-1) --
hl.window_rule({ match = { class = "^(firefox)$" },                           workspace = "1" })
hl.window_rule({ match = { class = "^(org.prismlauncher.PrismLauncher)$" },   workspace = "4" })

-- Super+C Communication Apps -> Workspace 3
hl.window_rule({ match = { class = "^(vesktop)$" },         workspace = "3 silent" })
hl.window_rule({ match = { class = "^(zapzap)$" },          workspace = "3 silent" })
hl.window_rule({ match = { class = "^(slack)$" },           workspace = "3 silent" })
hl.window_rule({ match = { class = "^(google-messages)$" }, workspace = "3 silent" })

-- Portable Monitor Apps (DP-1) --
hl.window_rule({ match = { class = "^(missioncenter)$" },            workspace = "8 silent",  monitor = "DP-1", maximize = true })
hl.window_rule({ match = { class = "^(Spotify)$" },                  workspace = "9 silent",  monitor = "DP-1" })
hl.window_rule({ match = { class = "^(org.pulseaudio.pavucontrol)$" }, workspace = "10 silent", monitor = "DP-1", tile = true })


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
hl.bind("SUPER + R",             hl.dsp.exec_cmd("~/.config/hypr/scripts/restart_desktop.sh"))
hl.bind(mainMod .. " + SUPER_L", hl.dsp.exec_cmd(menu), { repeating = true })
hl.bind(mainMod .. " + B",       hl.dsp.exec_cmd("blueman-manager"))
hl.bind(mainMod .. " + S",       hl.dsp.exec_cmd("~/.config/hypr/scripts/screenshot_noanim.sh region"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.exec_cmd("~/.config/hypr/scripts/screenshot_noanim.sh region"))
hl.bind("PRINT",                 hl.dsp.exec_cmd("~/.config/hypr/scripts/screenshot_noanim.sh full"))
hl.bind("SHIFT + PRINT",         hl.dsp.exec_cmd("~/.config/hypr/scripts/screenshot_noanim.sh region"))

hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"),  { repeating = true, locked = true })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),  { repeating = true, locked = true })
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

hl.bind(mainMod .. " + n",  hl.dsp.exec_cmd("swaync-client -t"))
hl.bind("SUPER + SHIFT + P", hl.dsp.exec_cmd("~/bin/kush_panic.sh"))

-- HyprEmoji config (from ~/.config/hypremoji/hypremoji.conf)
hl.bind("SUPER + period", hl.dsp.exec_cmd("hypremoji"))
hl.window_rule({ match = { title = "^(HyprEmoji)$" }, float = true })
hl.window_rule({ match = { title = "^(HyprEmoji)$" }, size  = "307 340" })
hl.window_rule({ match = { title = "^(HyprEmoji)$" }, move  = "1412 644" })
