#!/usr/bin/env bash

powered="$(bluetoothctl show 2>/dev/null | awk -F': ' '/Powered:/ {print $2; exit}')"

if [[ "$powered" != "yes" ]]; then
  echo '{"text":"󰂲 off","tooltip":"Bluetooth is off"}'
  exit 0
fi

connected_count="$(bluetoothctl devices Connected 2>/dev/null | wc -l)"
if [[ "$connected_count" -gt 0 ]]; then
  echo "{\"text\":\"󰂱 ${connected_count}\",\"tooltip\":\"Bluetooth connected devices: ${connected_count}\"}"
else
  echo '{"text":"󰂯 on","tooltip":"Bluetooth on (no connected devices)"}'
fi
