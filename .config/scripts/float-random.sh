#!/usr/bin/env bash
# float-random.sh — spawn an app floating; it glides smoothly to a random spot
# Usage: float-random.sh <app> [args...]
APP="$1"; shift
[ -z "$APP" ] && { echo "usage: float-random.sh <app> [args]"; exit 1; }

mapfile -t BEFORE < <(niri msg -j windows 2>/dev/null | jq -r '.[].id')
"$APP" "$@" &

# catch the new window fast (20ms polls)
ID=""
for _ in $(seq 1 40); do
    sleep 0.02
    mapfile -t NOW < <(niri msg -j windows 2>/dev/null | jq -r '.[].id')
    for w in "${NOW[@]}"; do
        found=no
        for b in "${BEFORE[@]}"; do [ "$w" = "$b" ] && found=yes && break; done
        [ "$found" = no ] && ID=$w && break
    done
    [ -n "$ID" ] && break
done
[ -z "$ID" ] && exit 0

sleep 0.05   # let niri assign its default position first

read -r SW SH < <(niri msg -j outputs 2>/dev/null | jq -r '[.. | .logical? // empty] | "\(.[0].width) \(.[0].height)"')
read -r WW WH X0 Y0 < <(niri msg -j windows 2>/dev/null | jq -r --argjson i "$ID" \
    '.[] | select(.id == $i) | .layout.window_size as $s |
     (.layout.tile_pos_in_workspace_view // [9999,9999]) as $p |
     "\($s[0]) \($s[1]) \($p[0]|floor) \($p[1]|floor)"' 2>/dev/null)
WW=${WW:-800}; WH=${WH:-450}; X0=${X0:-9999}; Y0=${Y0:-9999}

MARGIN=40
MAXX=$((SW - WW - MARGIN)); MAXY=$((SH - WH - MARGIN - 30))   # extra Y margin for waybar
[ "$MAXX" -le "$MARGIN" ] && MAXX=$MARGIN
[ "$MAXY" -le "$MARGIN" ] && MAXY=$MARGIN
TX=$((MARGIN + RANDOM % (MAXX - MARGIN)))
TY=$((MARGIN + RANDOM % (MAXY - MARGIN)))

# if we never got a valid start position, just place directly
if [ "$X0" = "9999" ] || [ "$Y0" = "9999" ]; then
    niri msg action move-floating-window --id "$ID" -x "$TX" -y "$TY" >/dev/null 2>&1
    exit 0
fi

# smooth ease-out glide (~200ms) from where it spawned to the random spot
STEPS=14
for k in $(seq 1 $STEPS); do
    p=$(awk "BEGIN{t=$k/$STEPS; printf \"%.4f\", 1-(1-t)*(1-t)}")
    cx=$(awk "BEGIN{printf \"%d\", $X0+($TX-$X0)*$p}")
    cy=$(awk "BEGIN{printf \"%d\", $Y0+($TY-$Y0)*$p}")
    niri msg action move-floating-window --id "$ID" -x "$cx" -y "$cy" >/dev/null 2>&1
done
