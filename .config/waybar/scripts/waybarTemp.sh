#!/usr/bin/env bash

TEMP=$(sensors | grep -m 1 'Package id 0' | awk '{print $4}' | tr -d '+°C')

if [[ -z "$TEMP" ]]; then
  TEMP=$(sensors | grep -m 1 'edge' | awk '{print $2}' | tr -d '+°C')
fi

if [[ -z "$TEMP" ]]; then
  CLASS="unknown"
  FORMAT="N/A°C"
  printf '{"text":"%s","class":"%s"}\n' "$FORMAT" "$CLASS"
  exit 0
fi

TEMP_INT=$(printf "%.0f" "$TEMP")

if (( TEMP_INT >= 70 )); then
  CLASS="critical"
  FORMAT="${TEMP_INT}°C"
else
  CLASS="normal"
  FORMAT="${TEMP_INT}°C"
fi

# print JSON with both text and class
printf '{"text":"%s","class":"%s"}\n' "$FORMAT" "$CLASS"
