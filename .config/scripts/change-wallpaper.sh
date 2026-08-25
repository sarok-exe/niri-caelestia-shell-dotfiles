#!/usr/bin/env bash
# Manually rotate to the next random wallpaper (once, no daemon).
set -u

WALLPAPER_DIR="$HOME/Pictures/Wallpapers"

# Ensure awww daemon is running
if ! pgrep -x awww-daemon >/dev/null 2>&1; then
    awww-daemon >/dev/null 2>&1 &
    sleep 0.5
fi

mapfile -t WALLS < <(find "$WALLPAPER_DIR" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) 2>/dev/null | sort)

if [ "${#WALLS[@]}" -eq 0 ]; then
    notify-send "Wallpaper" "No wallpapers found in $WALLPAPER_DIR" 2>/dev/null
    exit 1
fi

NEXT="${WALLS[$((RANDOM % ${#WALLS[@]}))]}"

awww img "$NEXT" \
    --transition-type fade \
    --transition-duration 2 \
    --transition-step 60 \
    --transition-fps 60

matugen image "$NEXT" --prefer darkness -q
