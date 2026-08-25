#!/bin/bash
PIDS=$(pgrep -f click-sound-daemon.py)
if [ -n "$PIDS" ]; then
    echo "$PIDS" | xargs kill
    notify-send "Click Sounds" "Disabled" -t 1500
else
    nohup python3 ~/.config/scripts/click-sound-daemon.py > /dev/null 2>&1 &
    notify-send "Click Sounds" "Enabled" -t 1500
fi
