#!/usr/bin/env bash

# ─────────────────────────────────────────────
# Config
# ─────────────────────────────────────────────
theme="$HOME/.config/rofi/styles/powermenu.rasi"
uptime="$(uptime -p | sed 's/up //')"

# ─────────────────────────────────────────────
# Options
# ─────────────────────────────────────────────
lock="  Lock"
sleep="󰏦  Sleep"
logout="󰿅  Logout"
reboot="  Reboot"
shutdown="󰐥  Shutdown"

yes="  Yes"
no="  No"

# ─────────────────────────────────────────────
# Rofi helpers
# ─────────────────────────────────────────────
rofi_menu() {
    rofi -dmenu \
        -p "Uptime: $uptime" \
        -theme "$theme"
}

confirm() {
    echo -e "$yes\n$no" | rofi -dmenu \
        -p "Confirmation" \
        -mesg "Are you sure?" \
        -theme "$theme"
}

# ─────────────────────────────────────────────
# Fake sleep (SAFE)
# ─────────────────────────────────────────────
fake_sleep() {
    mpc -q pause 2>/dev/null
    amixer set Master mute 2>/dev/null
    loginctl lock-session
    sleep 0.5
    hyprctl dispatch dpms off
}

# ─────────────────────────────────────────────
# Menu
# ─────────────────────────────────────────────
choice=$(echo -e "$lock\n$sleep\n$logout\n$reboot\n$shutdown" | rofi_menu)

case "$choice" in
    "$lock")
        ~/.config/hypr/scripts/lock
        ;;
    "$sleep")
        fake_sleep
        ;;
    "$logout")
        [[ "$(confirm)" == "$yes" ]] && hyprctl dispatch exit
        ;;
    "$reboot")
        [[ "$(confirm)" == "$yes" ]] && systemctl reboot
        ;;
    "$shutdown")
        [[ "$(confirm)" == "$yes" ]] && systemctl poweroff
        ;;
    *)
        exit 0
        ;;
esac
