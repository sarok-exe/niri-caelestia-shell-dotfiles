#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${HOME}/.config"

echo "==> Installing dotfiles from ${REPO_DIR} to ${TARGET}"

mkdir -p "$TARGET"

shopt -s dotglob nullglob
for item in "$REPO_DIR"/.config/*; do
    name="$(basename "$item")"
    dest="$TARGET/$name"

    if [[ -e "$dest" || -L "$dest" ]]; then
        if [[ -L "$dest" && "$(readlink "$dest")" == "$item" ]]; then
            echo "--  already linked: $name"
            continue
        fi
        backup="$TARGET/${name}.bak.$(date +%Y%m%d%H%M%S)"
        echo "!!  backing up existing $name -> $(basename "$backup")"
        mv "$dest" "$backup"
    fi

    ln -s "$item" "$dest"
    echo "++ linked $name"
done

# Seed wallpapers (bundled desert image). Never overwrites your own files.
if [[ -d "$REPO_DIR/wallpapers" ]]; then
    mkdir -p "$HOME/Pictures/Wallpapers"
    for w in "$REPO_DIR"/wallpapers/*; do
        base="$(basename "$w")"
        if [[ ! -e "$HOME/Pictures/Wallpapers/$base" ]]; then
            cp "$w" "$HOME/Pictures/Wallpapers/"
            echo "++ wallpaper added: $base"
        fi
    done
fi

cat <<'EOF'

Done! Restart your session (or run `niri` fresh) to apply.

A desert wallpaper was placed in ~/Pictures/Wallpapers — drop any
.jpg/.png/.webp in there and they rotate automatically.
Press Mod+Shift+W for the rofi wallpaper picker.

Recommended extras:
  sudo pacman -S --needed niri kitty fish starship waybar swaync rofi-wayland \
    yazi zathura zathura-pdf-mupdf mpv imv mousepad matugen fastfetch awww \
    wl-clipboard cliphist grim slurp tesseract tesseract-data-eng wlsunset \
    eza imagemagick
EOF
