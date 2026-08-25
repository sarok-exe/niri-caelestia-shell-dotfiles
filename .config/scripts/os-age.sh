#!/usr/bin/env bash
# Days since first pacman.log entry = rough OS install age.
# Lives outside matugen templates so nothing can corrupt its escaping.
log=/var/log/pacman.log
[ -r "$log" ] || { echo "?"; exit 0; }
first=$(head -n1 "$log" | tr -d '[]' | cut -c1-10)
case "$first" in
    ????-??-??) ;;
    *) echo "?"; exit 0 ;;
esac
d=$(( ($(date +%s) - $(date -d "$first" +%s)) / 86400 ))
if [ "$d" -ge 365 ]; then
    echo "$((d/365))y $((d%365))d"
else
    echo "$d days"
fi
