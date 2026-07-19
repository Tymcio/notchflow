#!/usr/bin/env bash
# Build a drag-to-Applications DMG: NotchFlow.app + Applications alias,
# with Finder icon layout (and optional background). After the user drags
# the app into Applications, macOS typically asks whether to eject the
# disk image / move it to Trash — that prompt is Finder, not us.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

source version.env

APP_PATH="${1:-$ROOT_DIR/build/${APP_NAME}.app}"
DMG_PATH="${2:-$ROOT_DIR/build/${APP_NAME}-${MARKETING_VERSION}.dmg}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Missing app bundle: $APP_PATH" >&2
  exit 1
fi

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/notchflow-dmg.XXXXXX")"
RW_DMG="$STAGE/rw.dmg"
MOUNT_ROOT="$STAGE/mount"
BG_DIR=""
cleanup() {
  if [[ -n "${DEVICE:-}" ]]; then
    hdiutil detach "$DEVICE" -force >/dev/null 2>&1 || true
  fi
  rm -rf "$STAGE"
}
trap cleanup EXIT

CONTENT="$STAGE/content"
mkdir -p "$MOUNT_ROOT" "$CONTENT"
cp -R "$APP_PATH" "$CONTENT/${APP_NAME}.app"
# Applications drop target is created as a Finder alias after mount (symlinks
# often refuse icon positioning in AppleScript).

# Optional brand background with a subtle arrow between the two drop zones.
BG_SRC="$ROOT_DIR/assets/dmg-background.png"
if [[ ! -f "$BG_SRC" ]]; then
  BG_SRC="$ROOT_DIR/Assets/dmg-background.png"
fi
if [[ ! -f "$BG_SRC" ]]; then
  python3 - "$STAGE/dmg-background.png" <<'PY' || true
from pathlib import Path
import sys
out = Path(sys.argv[1])
try:
    from PIL import Image, ImageDraw
except ImportError:
    raise SystemExit(0)

# Finder background coordinates are in points; 2x retina bitmap looks crisp.
w, h = 1200, 700
img = Image.new("RGB", (w, h), (18, 20, 28))
draw = ImageDraw.Draw(img)
# Soft panels behind the two icons
draw.rounded_rectangle((140, 150, 420, 520), radius=36, fill=(28, 32, 44))
draw.rounded_rectangle((780, 150, 1060, 520), radius=36, fill=(28, 32, 44))
# Arrow
ax0, ax1, ay = 460, 740, 340
draw.line([(ax0, ay), (ax1 - 40, ay)], fill=(90, 140, 255), width=14)
draw.polygon([(ax1 - 50, ay - 36), (ax1, ay), (ax1 - 50, ay + 36)], fill=(90, 140, 255))
# Accent wave under arrow (brand hint)
for i, color in enumerate([(56, 200, 255), (90, 120, 255), (170, 80, 255)]):
    y = 410 + i * 10
    draw.arc((480, y - 30, 720, y + 30), 200, 340, fill=color, width=4)
img.save(out, "PNG")
print(out)
PY
  if [[ -f "$STAGE/dmg-background.png" ]]; then
    BG_SRC="$STAGE/dmg-background.png"
  fi
fi

VOLUME_NAME="$APP_NAME"
rm -f "$RW_DMG" "$DMG_PATH"
mkdir -p "$(dirname "$DMG_PATH")"

# RW image large enough for Finder metadata + background.
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$CONTENT" \
  -fs HFS+ \
  -fsargs "-c c=64,a=16,e=16" \
  -format UDRW \
  -size 200m \
  "$RW_DMG" >/dev/null

# Attach without browsing so Finder window setup is deterministic.
# Detach any leftover volumes with the same name so AppleScript targets ours.
while hdiutil info | grep -q "/Volumes/${VOLUME_NAME}"; do
  hdiutil detach "/Volumes/${VOLUME_NAME}" -force >/dev/null 2>&1 || break
done

DEVICE="$(hdiutil attach -nobrowse -mountpoint "/Volumes/${VOLUME_NAME}" "$RW_DMG" | awk 'END { print $1 }')"
VOLUME_PATH="/Volumes/${VOLUME_NAME}"
if [[ ! -d "$VOLUME_PATH" ]]; then
  echo "Failed to mount DMG staging volume at $VOLUME_PATH" >&2
  exit 1
fi

rm -rf "$VOLUME_PATH/Applications"

if [[ -f "$BG_SRC" ]]; then
  BG_DIR="$VOLUME_PATH/.background"
  mkdir -p "$BG_DIR"
  # Finder background files should be uncompressed TIFF/PNG without @2x naming quirks.
  sips -s format png "$BG_SRC" --out "$BG_DIR/background.png" >/dev/null
fi

# Style the Finder window + create Applications alias. On headless CI this may
# fail — we still fall back to a POSIX symlink so drag-install works.
style_ok=0
if [[ "${SKIP_DMG_FINDER_STYLE:-0}" != "1" ]]; then
  for attempt in 1 2 3; do
    if osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOLUME_NAME"
    open
    delay 1
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    try
      set sidebar width of container window to 0
    end try
    set the bounds of container window to {200, 120, 800, 470}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    try
      set background picture of viewOptions to file ".background:background.png"
    end try
    -- Prefer a real Finder alias (positions reliably); remove any stale link first.
    try
      delete item "Applications"
    end try
    make new alias file at container window to POSIX file "/Applications" with properties {name:"Applications"}
    set position of item "${APP_NAME}.app" of container window to {150, 180}
    set position of item "Applications" of container window to {450, 180}
    update without registering applications
    delay 1
    close
    open
    delay 1
    close
  end tell
end tell
APPLESCRIPT
    then
      style_ok=1
      break
    fi
    echo "Finder DMG styling attempt $attempt failed; retrying…" >&2
    sleep 2
  done
fi

if [[ ! -e "$VOLUME_PATH/Applications" ]]; then
  ln -s /Applications "$VOLUME_PATH/Applications"
fi

sync
hdiutil detach "$DEVICE" -force >/dev/null
DEVICE=""

# Compress to final UDZO.
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null
# Convenience alias for Sparkle / latest download URL.
cp -f "$DMG_PATH" "$ROOT_DIR/build/${APP_NAME}.dmg"

if [[ "$style_ok" -eq 1 ]]; then
  echo "Created drag-to-Applications DMG (styled): $DMG_PATH"
else
  echo "Created drag-to-Applications DMG (Applications link only; Finder style skipped): $DMG_PATH"
fi
