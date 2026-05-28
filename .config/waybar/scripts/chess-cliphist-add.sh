#!/usr/bin/env bash
set -euo pipefail

HIST_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/chess-clipboard"
HIST_FILE="$HIST_DIR/history.tsv"
MAX_ITEMS=200

mkdir -p "$HIST_DIR"
touch "$HIST_FILE"

clip="$(cat)"
clip="${clip//$'\0'/}"

# Ignore empty or whitespace-only clipboard entries.
if [ -z "${clip//[[:space:]]/}" ]; then
  exit 0
fi

encoded="$(printf '%s' "$clip" | base64 -w0)"
tmp="$(mktemp)"

{
  printf '%s\t%s\n' "$(date +%s)" "$encoded"
  awk -F '\t' -v e="$encoded" '$2 != e' "$HIST_FILE"
} | head -n "$MAX_ITEMS" > "$tmp"

mv "$tmp" "$HIST_FILE"
