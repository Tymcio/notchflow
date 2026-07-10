#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

source version.env

BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/${APP_NAME}.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"

echo "Building release binary..."
swift build -c release --arch arm64

BIN_PATH="$ROOT_DIR/.build/arm64-apple-macosx/release/${APP_NAME}"
if [[ ! -f "$BIN_PATH" ]]; then
  BIN_PATH="$ROOT_DIR/.build/release/${APP_NAME}"
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"

cp "$BIN_PATH" "$MACOS_DIR/${APP_NAME}"
chmod +x "$MACOS_DIR/${APP_NAME}"

# Copy Sparkle framework — required at runtime (@rpath)
SPARKLE_FW=""
for candidate in \
  "$ROOT_DIR/.build/arm64-apple-macosx/release/Sparkle.framework" \
  "$ROOT_DIR/.build/release/Sparkle.framework" \
  "$ROOT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"; do
  if [[ -d "$candidate" ]]; then
    SPARKLE_FW="$candidate"
    break
  fi
done

if [[ -n "$SPARKLE_FW" ]]; then
  rm -rf "$FRAMEWORKS_DIR/Sparkle.framework"
  cp -R "$SPARKLE_FW" "$FRAMEWORKS_DIR/"
  # Ensure the binary can find Contents/Frameworks at runtime
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/${APP_NAME}" 2>/dev/null || true
  echo "Bundled Sparkle.framework"
else
  echo "WARNING: Sparkle.framework not found — app will crash on launch." >&2
fi

LS_UI_ELEMENT="false"
if [[ "${MENU_BAR_APP:-0}" == "1" ]]; then
  LS_UI_ELEMENT="true"
fi

SPARKLE_PLIST=""
if [[ -n "${SPARKLE_PUBLIC_ED_KEY:-}" ]]; then
  SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-https://notchflow.eu/appcast.xml}"
  SPARKLE_PLIST="$(cat <<SPARKLE
  <key>SUFeedURL</key>
  <string>${SPARKLE_FEED_URL}</string>
  <key>SUPublicEDKey</key>
  <string>${SPARKLE_PUBLIC_ED_KEY}</string>
SPARKLE
)"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${MARKETING_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <${LS_UI_ELEMENT}/>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © 2026 NotchFlow. All rights reserved.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
${SPARKLE_PLIST}
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key>
      <string>${BUNDLE_ID}</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>notchflow</string>
      </array>
    </dict>
  </array>
  <key>NSAppleEventsUsageDescription</key>
  <string>NotchFlow controls Spotify and Music playback when you grant Automation access.</string>
  <key>NSCalendarsUsageDescription</key>
  <string>NotchFlow shows upcoming calendar events in the notch island.</string>
  <key>NSCameraUsageDescription</key>
  <string>NotchFlow shows a live camera preview in the Camera Mirror module.</string>
</dict>
</plist>
PLIST

echo "Packaged: $APP_DIR"
