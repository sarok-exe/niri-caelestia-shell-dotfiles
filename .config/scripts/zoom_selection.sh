#!/bin/bash
# Toggle Niri output scale between 1x and 2x zoom

output="LVDS-1"
current=$(niri msg outputs | grep -A8 "^Output.*($output)" | grep "Scale:" | awk '{print $2}')

if python3 -c "exit(0 if abs($current - 1) < 0.001 else 1)" 2>/dev/null; then
    niri msg output "$output" scale 2
else
    niri msg output "$output" scale 1
fi
