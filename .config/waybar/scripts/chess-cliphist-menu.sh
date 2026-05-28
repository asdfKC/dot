#!/usr/bin/env bash
set -euo pipefail

HIST_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/chess-clipboard"
HIST_FILE="$HIST_DIR/history.tsv"
DAEMON_SCRIPT="$HOME/.config/waybar/scripts/chess-cliphist-daemon.sh"

mkdir -p "$HIST_DIR"
touch "$HIST_FILE"

if ! command -v fzf >/dev/null 2>&1; then
  echo "♟ fzf is required for chess clipboard history."
  echo "Install fzf and try again."
  read -r -n 1 -p "Press any key to close..." _
  echo
  exit 1
fi

if ! command -v wl-copy >/dev/null 2>&1; then
  echo "♟ wl-copy is required."
  read -r -n 1 -p "Press any key to close..." _
  echo
  exit 1
fi

if ! pgrep -f "chess-cliphist-daemon.sh" >/dev/null 2>&1; then
  nohup "$DAEMON_SCRIPT" >/dev/null 2>&1 &
fi

if [ ! -s "$HIST_FILE" ]; then
  echo "♜ Chess Clipboard"
  echo "No moves recorded yet. Copy something first."
  read -r -n 1 -p "Press any key to close..." _
  echo
  exit 0
fi

selection="$(
  while IFS=$'\t' read -r ts b64; do
    [ -z "${b64:-}" ] && continue
    decoded="$(printf '%s' "$b64" | base64 -d 2>/dev/null || true)"
    clean="$(printf '%s' "$decoded" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g')"
    [ -z "${clean//[[:space:]]/}" ] && clean="(binary/empty entry)"
    short="$(printf '%s' "$clean" | cut -c1-72)"
    printf '%s\t%s\n' "$b64" "$short"
  done < "$HIST_FILE"
)"

picked="$(printf '%s\n' "$selection" | fzf \
  --delimiter=$'\t' \
  --with-nth=2 \
  --height=55% \
  --layout=reverse \
  --border=rounded \
  --prompt='♞ Select move > ' \
  --info=inline-right \
  --header='♔ Chess Clipboard History (Enter to copy)' \
  --color='fg:#f2e7c9,bg:#0b0d10,hl:#d4af37,fg+:#f7ecd0,bg+:#1a1f27,hl+:#f1d27c,prompt:#d4af37,pointer:#d4af37,header:#caa55a,border:#d4af37')"

[ -z "$picked" ] && exit 0
chosen_b64="${picked%%$'\t'*}"

printf '%s' "$chosen_b64" | base64 -d 2>/dev/null | wl-copy
notify-send "♛ Chess Clipboard" "Move copied to clipboard"
