#!/bin/bash
# Rofi app launcher — uses matugen-generated grimm theme (falls back to static)
THEME="$HOME/.cache/matugen/rofi/grimm.rasi"
[ -f "$THEME" ] || THEME="$HOME/.config/rofi/themes/grimm-blue.rasi"
exec rofi -show drun -show-icons -theme "$THEME" "$@"
