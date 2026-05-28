#!/usr/bin/env sh

url="https://www.chess.com/home"

if command -v google-chrome-stable >/dev/null 2>&1; then
    exec google-chrome-stable --new-window --app="$url"
fi

if command -v chromium >/dev/null 2>&1; then
    exec chromium --new-window --app="$url"
fi

if command -v chromium-browser >/dev/null 2>&1; then
    exec chromium-browser --new-window --app="$url"
fi

notify-send "Chess launcher" "No Chromium-based browser found."
