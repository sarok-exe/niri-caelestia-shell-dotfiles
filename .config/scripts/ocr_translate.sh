#!/usr/bin/env bash
set -euo pipefail

TMPFILE=$(mktemp /tmp/ocr-XXXXXX.png)
trap 'rm -f "$TMPFILE"' EXIT

LENS_SCAN="${LENS_SCAN:-$(command -v lens_scan || echo ~/.local/share/pipx/venvs/chrome-lens-py/bin/lens_scan)}"

grim -g "$(slurp)" "$TMPFILE"

OUTPUT=$("$LENS_SCAN" "$TMPFILE" --translate ar 2>/dev/null)

TEXT=$(echo "$OUTPUT" | sed -n '/OCR Results:/,/Translated Text:/p' | sed '1d;$d')
RESULT=$(echo "$OUTPUT" | sed -n '/Translated Text:/,$p' | tail -n +2)

if [ -z "$TEXT" ]; then
    notify-send "Translation" "No text detected" -t 2000
    exit 1
fi

if echo "$TEXT" | python3 -c "import sys; sys.exit(0 if any('\u0600' <= c <= '\u06FF' for c in sys.stdin.read()) else 1)" 2>/dev/null; then
    RESULT=$("$LENS_SCAN" "$TMPFILE" --translate en 2>/dev/null | sed -n '/Translated Text:/,$p' | tail -n +2)
fi

if [ -z "$RESULT" ]; then
    notify-send "Translation Failed" "No translation returned" -t 3000
    exit 1
fi

wl-copy "$RESULT"
notify-send "Translate done!" "$RESULT" -t 3500
