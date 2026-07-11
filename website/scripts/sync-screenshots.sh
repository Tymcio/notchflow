#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$ROOT/screeny notchflow pl"
DST="$ROOT/website/assets/screenshots"

copy() {
  cp "$SRC/notchflow screeny pl $1.png" "$DST/$2"
}

copy 2 01-music.png
copy 3 02-calendar.png
copy 4 03-shelf.png
copy 5 04-timer.png
copy 6 05-stopwatch.png
copy 7 06-pomodoro.png
copy 8 07-notes.png
copy 9 08-clipboard.png
copy 1 09-camera.png

echo "Screenshots synced to $DST (raw, bez przetwarzania)"
