#!/usr/bin/env bash

set -euo pipefail

menu_title="󰂯  Bluetooth"
style_path="$HOME/.config/wofi/bluetooth-menu.css"

powered="$(bluetoothctl show 2>/dev/null | awk -F': ' '/Powered:/ {print $2; exit}' || true)"

get_devices() {
  bluetoothctl "$@" 2>/dev/null | awk '/^Device / {print}'
}

declare -a options

if [[ "$powered" != "yes" ]]; then
  options+=("󰂯  Turn Bluetooth On")
else
  options+=("󰂲  Turn Bluetooth Off")

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    mac="$(awk '{print $2}' <<<"$line")"
    name="${line#Device $mac }"
    [[ "$name" == "$line" || -z "$name" ]] && name="Unknown Device"
    options+=("󰂳  Disconnect: ${name} (${mac})")
  done < <(get_devices devices Connected)

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    mac="$(awk '{print $2}' <<<"$line")"
    name="${line#Device $mac }"
    [[ "$name" == "$line" || -z "$name" ]] && name="Unknown Device"
    if ! bluetoothctl info "$mac" 2>/dev/null | grep -q "Connected: yes"; then
      options+=("󰂱  Connect: ${name} (${mac})")
    fi
  done < <(get_devices devices Paired)
fi

options+=("  Open Bluetooth Manager")

choice="$(printf '%s\n' "${options[@]}" | wofi --dmenu --prompt "$menu_title" --style "$style_path" --lines 14 --width 700)"
[[ -z "$choice" ]] && exit 0

case "$choice" in
  "󰂯  Turn Bluetooth On")
    if bluetoothctl power on >/dev/null 2>&1; then
      notify-send "Bluetooth" "Powered on"
    else
      notify-send "Bluetooth" "Failed to power on"
    fi
    ;;
  "󰂲  Turn Bluetooth Off")
    if bluetoothctl power off >/dev/null 2>&1; then
      notify-send "Bluetooth" "Powered off"
    else
      notify-send "Bluetooth" "Failed to power off"
    fi
    ;;
  "  Open Bluetooth Manager")
    blueman-manager >/dev/null 2>&1 &
    ;;
  *"Connect:"*)
    mac="$(sed -n 's/.*(\(.*\))$/\1/p' <<<"$choice")"
    if [[ -n "$mac" ]] && bluetoothctl connect "$mac" >/dev/null 2>&1; then
      notify-send "Bluetooth" "Connected: ${mac}"
    else
      notify-send "Bluetooth" "Failed to connect"
    fi
    ;;
  *"Disconnect:"*)
    mac="$(sed -n 's/.*(\(.*\))$/\1/p' <<<"$choice")"
    if [[ -n "$mac" ]] && bluetoothctl disconnect "$mac" >/dev/null 2>&1; then
      notify-send "Bluetooth" "Disconnected: ${mac}"
    else
      notify-send "Bluetooth" "Failed to disconnect"
    fi
    ;;
esac
