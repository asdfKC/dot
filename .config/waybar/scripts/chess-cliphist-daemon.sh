#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ADD_SCRIPT="$SCRIPT_DIR/chess-cliphist-add.sh"

if [ ! -x "$ADD_SCRIPT" ]; then
  echo "chess-cliphist: missing add script at $ADD_SCRIPT" >&2
  exit 1
fi

# Watch Wayland clipboard changes and append them to history.
exec wl-paste --type text --watch "$ADD_SCRIPT"
