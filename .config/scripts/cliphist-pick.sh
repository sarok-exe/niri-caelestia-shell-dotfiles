#!/usr/bin/env bash
# Pick from clipboard history (cliphist) via rofi, copy the selection.
set -u

HIST="$(cliphist list 2>/dev/null)"
if [ -z "$HIST" ]; then
    notify-send "Clipboard" "History is empty" -t 2000
    exit 0
fi

SEL="$(printf '%s\n' "$HIST" | rofi -dmenu -i -p " Clipboard" -theme-str 'window { width: 32%; location: center; } listview { lines: 15; }')"
[ -n "$SEL" ] || exit 0

printf '%s\n' "$SEL" | cliphist decode | wl-copy
