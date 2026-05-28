#!/usr/bin/env bash

set -euo pipefail

default_if="$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i == "dev") {print $(i+1); exit}}')"
if [[ -z "${default_if}" ]]; then
  notify-send "Network" "No active network route"
  exit 0
fi

local_ip="$(ip -4 -o addr show dev "${default_if}" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)"
gateway="$(ip route 2>/dev/null | awk '/^default/ {print $3; exit}')"

ssid=""
if command -v nmcli >/dev/null 2>&1; then
  ssid="$(nmcli -t -f active,ssid dev wifi 2>/dev/null | awk -F: '$1=="yes"{print $2; exit}')"
fi

if [[ "${default_if}" == wl* ]] || [[ -n "${ssid}" ]]; then
  title="Wi-Fi"
else
  title="Ethernet"
fi

message="Interface: ${default_if}"
if [[ -n "${local_ip}" ]]; then
  message+=$'\nIP: '
  message+="${local_ip}"
fi
if [[ -n "${gateway}" ]]; then
  message+=$'\nGateway: '
  message+="${gateway}"
fi
if [[ -n "${ssid}" ]]; then
  message+=$'\nSSID: '
  message+="${ssid}"
fi

notify-send "${title}" "${message}"
