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
codesign --force --options runtime --timestamp \
  --entitlements "$ROOT_DIR/NotchFlow.entitlements" \
  --sign "$DEVELOPER_ID_APPLICATION" \
  "$APP_PATH/Contents/Frameworks/"*.framework 2>/dev/null || true

codesign --force --options runtime --timestamp \
  --entitlements "$ROOT_DIR/NotchFlow.entitlements" \
  --sign "$DEVELOPER_ID_APPLICATION" \
  "$APP_PATH"

echo "Creating DMG..."
hdiutil create -volname "$APP_NAME" -srcfolder "$APP_PATH" -ov -format UDZO "$DMG_PATH"

echo "Notarizing..."
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

echo "Stapling..."
xcrun stapler staple "$DMG_PATH"

echo "Release artifact: $DMG_PATH"
shasum -a 256 "$DMG_PATH"
