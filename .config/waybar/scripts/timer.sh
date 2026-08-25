#!/bin/bash
STATE_FILE="/tmp/waybar-timer-start"
LAST_BEEP_FILE="/tmp/waybar-last-beep"

case "${1:-}" in
    toggle)
        if [[ -f "$STATE_FILE" ]]; then
            rm -f "$STATE_FILE" "$LAST_BEEP_FILE"
        else
            date +%s > "$STATE_FILE"
        fi
        exit 0
        ;;
    reset)
        rm -f "$STATE_FILE" "$LAST_BEEP_FILE"
        exit 0
        ;;
esac

exec python3 -u -c "
import os, time, json, subprocess

state = '$STATE_FILE'
last_beep_file = '$LAST_BEEP_FILE'
beep_sound = '/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga'

while True:
    if os.path.exists(state):
        start = int(open(state).read().strip())
        elapsed = int(time.time()) - start
        m, s = divmod(elapsed, 60)

        # Every 10 minutes: play beep
        if m > 0 and m % 10 == 0:
            last_beep = int(open(last_beep_file).read().strip()) if os.path.exists(last_beep_file) else -1
            if last_beep != m:
                # Play notification sound (async, don't block)
                subprocess.Popen(['paplay', beep_sound],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                open(last_beep_file, 'w').write(str(m))

        print(json.dumps({'text': f'{m:02d}:{s:02d}', 'tooltip': 'running — Left: pause  Right: reset'}))
    else:
        print(json.dumps({'text': '00:00', 'tooltip': 'stopped — Left: start  Right: reset'}))

    time.sleep(1)
" 2>/dev/null
