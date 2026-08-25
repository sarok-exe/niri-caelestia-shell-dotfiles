#!/usr/bin/env bash
# 24/7 eye protection + vibrancy boost
# Warm temperature for eye comfort + slight gamma boost for vivid colors.
pkill -x redshift 2>/dev/null
pkill -x wlsunset 2>/dev/null
sleep 0.5
# wlsunset: Wayland-native blue light filter
# -t 2000     = night temperature (deep orange)
# -T 2700     = day temperature — still very warm, all the time
# -g 1.1      = slight gamma boost for vivid/saturated colors
exec wlsunset -t 2000 -T 2700 -g 1.1
