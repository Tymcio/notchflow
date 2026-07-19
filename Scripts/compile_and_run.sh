#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

source version.env

"$ROOT_DIR/Scripts/package_app.sh"

APP_PATH="$ROOT_DIR/build/${APP_NAME}.app"
BIN_PATH="$APP_PATH/Contents/MacOS/${APP_NAME}"

# Ubij wszystkie instancje (menu bar app bywa trudna do złapania samym pkill -x).
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 0.4
pkill -9 -x "$APP_NAME" 2>/dev/null || true

echo "Launching: $APP_PATH"
echo "Version: ${MARKETING_VERSION} (${BUILD_NUMBER})"
echo "Binary mtime: $(stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "$BIN_PATH")"
ICON_RESOLVER="$(/usr/libexec/PlistBuddy -c 'Print :NFNotificationIconResolver' "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
if [[ "$ICON_RESOLVER" == "v35" ]]; then
  echo "Verified: notification icon resolver $ICON_RESOLVER in Info.plist"
else
  echo "WARNING: NFNotificationIconResolver missing from Info.plist — build may be stale (got: ${ICON_RESOLVER:-none})" >&2
fi

open "$APP_PATH"
