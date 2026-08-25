#!/usr/bin/env bash
TMPFILE=$(mktemp /tmp/ocr-XXXXXX.png)
grim -g "$(slurp)" "$TMPFILE"
tesseract "$TMPFILE" stdout -l eng 2>/dev/null | wl-copy
notify-send "OCR" "Text copied to clipboard" -t 2000
rm "$TMPFILE"
