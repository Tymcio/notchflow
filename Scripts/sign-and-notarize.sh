#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

source version.env

: "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE}"

APP_PATH="$ROOT_DIR/build/${APP_NAME}.app"
DMG_PATH="$ROOT_DIR/build/${APP_NAME}-${MARKETING_VERSION}.dmg"

ENFORCE_LICENSE=1 "$ROOT_DIR/Scripts/package_app.sh"

echo "Signing app..."
SPARKLE_FW="$APP_PATH/Contents/Frameworks/Sparkle.framework"
if [[ -d "$SPARKLE_FW" ]]; then
  echo "Signing Sparkle helpers..."
  # Sign nested helper tools + XPCs first, then the framework itself.
  for item in \
    "$SPARKLE_FW/Versions/B/Autoupdate" \
    "$SPARKLE_FW/Versions/B/Updater.app" \
    "$SPARKLE_FW/Versions/B/XPCServices/"*.xpc \
    "$SPARKLE_FW/Versions/B/Updater.app/Contents/XPCServices/"*.xpc; do
    if [[ -e "$item" ]]; then
      codesign --force --options runtime --timestamp \
        --sign "$DEVELOPER_ID_APPLICATION" \
        "$item"
    fi
  done
fi

echo "Signing embedded frameworks..."
codesign --force --options runtime --timestamp \
  --entitlements "$ROOT_DIR/NotchFlow.entitlements" \
  --sign "$DEVELOPER_ID_APPLICATION" \
  "$APP_PATH/Contents/Frameworks/"*.framework

codesign --force --options runtime --timestamp \
  --entitlements "$ROOT_DIR/NotchFlow.entitlements" \
  --sign "$DEVELOPER_ID_APPLICATION" \
  "$APP_PATH"

echo "Creating DMG..."
hdiutil create -volname "$APP_NAME" -srcfolder "$APP_PATH" -ov -format UDZO "$DMG_PATH"

echo "Notarizing..."
NOTARY_JSON="$(mktemp -t notchflow-notary.XXXXXX.json)"
if xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json >"$NOTARY_JSON"; then
  true
else
  echo "Notary submission failed. Raw output:"
  cat "$NOTARY_JSON" || true
  exit 1
fi

SUBMISSION_ID="$(python3 - "$NOTARY_JSON" <<'PY'
import json
import sys
path = sys.argv[1] if len(sys.argv) > 1 else ""
if not path:
    raise SystemExit("missing json path arg")
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)
print(data.get("id", ""))
PY
)"

STATUS="$(python3 - "$NOTARY_JSON" <<'PY'
import json
import sys
path = sys.argv[1] if len(sys.argv) > 1 else ""
if not path:
    raise SystemExit("missing json path arg")
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)
print(data.get("status", ""))
PY
)"

echo "Notary submission id: ${SUBMISSION_ID}"
echo "Notary status: ${STATUS}"

if [[ -n "$SUBMISSION_ID" ]] && [[ "$STATUS" != "Accepted" ]]; then
  echo "Notary log for ${SUBMISSION_ID}:"
  xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" || true
  exit 1
fi

echo "Stapling..."
xcrun stapler staple "$DMG_PATH"

echo "Release artifact: $DMG_PATH"
shasum -a 256 "$DMG_PATH"
