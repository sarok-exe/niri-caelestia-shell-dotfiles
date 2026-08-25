#!/usr/bin/env bash
# Wallpaper picker: rofi grid -> awww transition -> full re-theme via matugen.
set -u

WALL_DIR="${WALLPAPER_DIR:-$HOME/Pictures/Wallpapers}"

notify() { command -v notify-send >/dev/null 2>&1 && notify-send "$@"; }

command -v rofi >/dev/null 2>&1 || { notify "Wallpaper" "rofi is not installed"; exit 1; }
[ -d "$WALL_DIR" ] || { notify "Wallpaper" "No wallpaper folder at $WALL_DIR"; exit 1; }

list_walls() {
    cd "$WALL_DIR" || exit 1
    for f in *.jpg *.jpeg *.png *.webp; do
        [ -e "$f" ] || continue
        printf '%s\0icon\x1f%s\n' "$f" "$WALL_DIR/$f"
    done
}

CHOICE=$(list_walls | rofi -dmenu -i -p "Wallpaper" \
    -theme-str "
    window { width: 65%; height: 80%; }
    listview { columns: 4; lines: 2; spacing: 5px; padding: 5px; }
    element { orientation: vertical; padding: 5px; border-radius: 15px; }
    element-icon { size: 250px; horizontal-align: 0.5; }
")

[ -z "${CHOICE:-}" ] && exit 0
WALL="$WALL_DIR/$CHOICE"
[ -f "$WALL" ] || { notify "Wallpaper" "File vanished: $CHOICE"; exit 1; }

# Stop video wallpapers before setting an image one
pgrep -x mpvpaper >/dev/null 2>&1 && pkill mpvpaper

if command -v awww >/dev/null 2>&1; then
    pgrep -x awww-daemon >/dev/null 2>&1 || { awww-daemon >/dev/null 2>&1 & sleep 0.5; }
    awww img "$WALL" --transition-type random --transition-step 90 --transition-fps 60
    if [ "${XDG_CURRENT_DESKTOP:-}" = "niri" ] && command -v magick >/dev/null 2>&1; then
        magick "${WALL}[0]" -background black -alpha remove \
            -set option:filter:blur 1.0 -blur 0x15 /tmp/backdrop.jpg &&
            awww img -n awww-daemon-backdrop /tmp/backdrop.jpg
    fi
else
    notify "Wallpaper" "awww is not installed"
fi

# Re-theme everything from the new image (kitty + waybar reload via hooks).
if command -v matugen >/dev/null 2>&1; then
    matugen image "$WALL" --prefer darkness >/dev/null 2>&1 ||
        matugen image "$WALL" >/dev/null 2>&1 || true
fi

# Best-effort: font/GTK bits from the haku theme chain if present
[ -x "$HOME/.local/bin/apply_style.sh" ] &&
    "$HOME/.local/bin/apply_style.sh" >/dev/null 2>&1 || true

notify "Wallpaper" "$CHOICE"
