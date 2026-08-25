#!/usr/bin/env bash
FLAG="/tmp/.battery-logout-triggered"
BAT="/sys/class/power_supply/BAT0"
THRESHOLD=15
GRACE=30
INTERVAL=60

while true; do
    capacity=$(cat "$BAT/capacity" 2>/dev/null) || break
    status=$(cat "$BAT/status" 2>/dev/null) || break

    if [ "$status" = "Charging" ] || [ "$capacity" -gt "$THRESHOLD" ]; then
        rm -f "$FLAG"
    fi

    if [ "$status" = "Discharging" ] && [ "$capacity" -le "$THRESHOLD" ] && [ ! -f "$FLAG" ]; then
        touch "$FLAG"
        notify-send -u critical "Battery Critical" "Battery at ${capacity}%. Logging out in ${GRACE}s — plug in now!"
        sleep "$GRACE"
        capacity=$(cat "$BAT/capacity" 2>/dev/null)
        status=$(cat "$BAT/status" 2>/dev/null)
        if [ "$status" = "Discharging" ] && [ "$capacity" -le "$THRESHOLD" ]; then
            systemctl suspend
        fi
    fi

    sleep "$INTERVAL"
done
