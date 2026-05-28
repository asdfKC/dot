#!/usr/bin/env bash
# Chess WiFi Manager — nmcli + wofi

WOFI_STYLE="$HOME/.config/wofi/wifi-style.css"

# Signal strength → chess piece rank
signal_piece() {
  local sig=$1
  if   [ "$sig" -ge 80 ]; then echo "♛"   # Queen  — excellent
  elif [ "$sig" -ge 60 ]; then echo "♞"   # Knight — good
  elif [ "$sig" -ge 40 ]; then echo "♝"   # Bishop — fair
  elif [ "$sig" -ge 20 ]; then echo "♜"   # Rook   — weak
  else                         echo "♟"   # Pawn   — poor
  fi
}

# Security icon
sec_icon() {
  [ -z "$1" ] && echo "○" || echo "●"
}

# Scan networks — deduplicate by SSID, pick best signal
declare -A seen
ENTRIES=""
while IFS=: read -r active ssid signal security; do
  [ -z "$ssid" ] && continue
  [ "${seen[$ssid]+_}" ] && continue
  seen["$ssid"]=1
  piece=$(signal_piece "$signal")
  lock=$(sec_icon "$security")
  prefix="  "; [ "$active" = "yes" ] && prefix="♔ "
  ENTRIES+="${prefix}${piece}  ${lock}  ${ssid}   (${signal}%)\n"
done < <(nmcli -t -f active,ssid,signal,security dev wifi list 2>/dev/null | sort -t: -k3 -nr)

# Handle disconnect / rescan options
ENTRIES+="─────────────────────────\n"
ENTRIES+="♚  Disconnect\n"
ENTRIES+="↻  Rescan\n"

CHOICE=$(printf "%b" "$ENTRIES" | wofi \
  --dmenu \
  --style="$WOFI_STYLE" \
  --prompt="♞  Select network" \
  --width=480 \
  --height=360 \
  --location=center \
  --lines=10 \
  --allow-markup=false \
  --insensitive=true)

[ -z "$CHOICE" ] && exit 0

# Strip leading symbols/spaces to extract plain SSID
SSID=$(echo "$CHOICE" | sed 's/^[♔♛♞♝♜♟○● ─↻♚]*//;s/   (.*)//' | xargs)

if echo "$CHOICE" | grep -q "Disconnect"; then
  nmcli dev disconnect "$(nmcli -t -f device,type dev | grep ':wifi' | cut -d: -f1 | head -1)"
  notify-send "♟ Chess WiFi" "Disconnected"
  exit 0
fi

if echo "$CHOICE" | grep -q "Rescan"; then
  nmcli dev wifi rescan 2>/dev/null
  exec "$0"
  exit 0
fi

[ -z "$SSID" ] && exit 0

# Try to connect — saved profile first, then ask for password
if nmcli con up "$SSID" 2>/dev/null; then
  notify-send "♛ Chess WiFi" "Connected to $SSID"
else
  PASS=$(echo "" | wofi \
    --dmenu \
    --style="$WOFI_STYLE" \
    --prompt="♝  Password for $SSID" \
    --width=420 \
    --height=80 \
    --location=center \
    --lines=1 \
    --password)

  [ -z "$PASS" ] && exit 0

  if nmcli dev wifi connect "$SSID" password "$PASS" 2>/dev/null; then
    notify-send "♛ Chess WiFi" "Connected to $SSID"
  else
    notify-send -u critical "♟ Chess WiFi" "Failed to connect to $SSID"
  fi
fi
