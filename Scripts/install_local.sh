#!/usr/bin/env bash
# Install a local (non-notarized) build into /Applications and clear Gatekeeper
# quarantine so it can launch. Official releases still need Developer ID + notarize.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
source version.env

APP_SRC="${1:-$ROOT_DIR/build/${APP_NAME}.app}"
APP_DST="/Applications/${APP_NAME}.app"

if [[ ! -d "$APP_SRC" ]]; then
  echo "Missing app bundle: $APP_SRC" >&2
  echo "Run Scripts/package_app.sh (or compile_and_run.sh) first." >&2
  exit 1
fi

pkill -x "$APP_NAME" 2>/dev/null || true
sleep 0.3

echo "Installing $APP_SRC → $APP_DST"
rm -rf "$APP_DST"
cp -R "$APP_SRC" "$APP_DST"

# DMG / download copies get com.apple.quarantine; Apple Development builds
# are not notarized, so Gatekeeper blocks "Open" until quarantine is cleared.
xattr -cr "$APP_DST"
# Explicitly drop quarantine if still present on older macOS.
xattr -d com.apple.quarantine "$APP_DST" 2>/dev/null || true

echo "Launching $APP_DST"
open "$APP_DST"
echo "Installed local build (quarantine cleared)."
