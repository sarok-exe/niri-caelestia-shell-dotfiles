#!/usr/bin/env bash
# Rotate the wallpaper every 30 minutes with a fade transition.
# Uses awww (awww-daemon + awww img); runs as a singleton (flock).
set -u

WALLPAPER_DIR="$HOME/Pictures/Wallpapers"
INTERVAL=1800
LAST=""
TRANSITION_DURATION=2

LOCK="${XDG_RUNTIME_DIR:-/tmp}/wallpaper-rotate.lock"
exec 9>"$LOCK"
if ! flock -n 9; then
    exit 0
fi

# Make sure the awww daemon is running (fd 9 = our lock, so close it in the daemon).
if ! pgrep -x awww-daemon >/dev/null 2>&1; then
    awww-daemon >/dev/null 2>&1 9>&- &
    sleep 0.5
fi

while true; do
    mapfile -t WALLS < <(find "$WALLPAPER_DIR" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) 2>/dev/null | sort)

    if [ "${#WALLS[@]}" -eq 0 ]; then
        echo "[wallpaper-rotate] no wallpapers found in $WALLPAPER_DIR" >&2
        exit 1
    fi

    NEXT="${WALLS[$((RANDOM % ${#WALLS[@]}))]}"
    while [ "$NEXT" = "$LAST" ] && [ "${#WALLS[@]}" -gt 1 ]; do
        NEXT="${WALLS[$((RANDOM % ${#WALLS[@]}))]}"
    done
    LAST="$NEXT"

    awww img "$NEXT" \
        --transition-type fade \
        --transition-duration "$TRANSITION_DURATION" \
        --transition-step 60 \
        --transition-fps 60

    matugen image "$NEXT" --prefer darkness -q

    sleep "$INTERVAL"
done
