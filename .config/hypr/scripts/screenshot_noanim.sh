#!/usr/bin/env bash

set -u

mode="${1:-full}"
save_dir="$(xdg-user-dir PICTURES)/Screenshots"

mkdir -p "$save_dir"
filename="Screenshot_$(date '+%Y-%m-%d_%H.%M.%S').png"
save_path="$save_dir/$filename"

restore_animations() {
    hyprctl keyword animations:enabled 1 >/dev/null 2>&1 || true
}

hyprctl keyword animations:enabled 0 >/dev/null 2>&1 || true
trap restore_animations EXIT

sleep 0.05

if [[ "$mode" == "region" ]]; then
    geometry="$(slurp)"
    [[ -z "$geometry" ]] && exit 0
    grim -g "$geometry" "$save_path"
else
    grim "$save_path"
fi

wl-copy --type image/png < "$save_path"
