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

# Copy SPM resource bundle (icons, String Catalog localizations)
RESOURCE_BUNDLE=""
for candidate in \
  "$ROOT_DIR/.build/arm64-apple-macosx/release/NotchFlow_NotchFlow.bundle" \
  "$ROOT_DIR/.build/release/NotchFlow_NotchFlow.bundle"; do
  if [[ -d "$candidate" ]]; then
    RESOURCE_BUNDLE="$candidate"
    break
  fi
done

if [[ -n "$RESOURCE_BUNDLE" ]]; then
  rm -rf "$RESOURCES_DIR/NotchFlow_NotchFlow.bundle"
  cp -R "$RESOURCE_BUNDLE" "$RESOURCES_DIR/"
  echo "Bundled NotchFlow_NotchFlow.bundle"
else
  echo "WARNING: NotchFlow_NotchFlow.bundle not found — icons and localizations may be missing." >&2
fi

# App icon (.icns) — without CFBundleIconFile macOS shows the gray template placeholder.
APP_ICON_SRC=""
for candidate in \
  "$ROOT_DIR/Assets/AppIcon.png" \
  "$ROOT_DIR/assets/AppIcon.png" \
  "$ROOT_DIR/ikonka.png"; do
  if [[ -f "$candidate" ]]; then
    APP_ICON_SRC="$candidate"
    break
  fi
done

if [[ -n "$APP_ICON_SRC" ]]; then
  ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
  rm -rf "$ICONSET_DIR"
  mkdir -p "$ICONSET_DIR"
  # Pad/crop to square master, then generate the iconset sizes Apple expects.
  MASTER_PNG="$BUILD_DIR/AppIcon-1024.png"
  sips -z 1024 1024 "$APP_ICON_SRC" --out "$MASTER_PNG" >/dev/null
  declare -a ICON_SIZES=(16 32 128 256 512)
  for size in "${ICON_SIZES[@]}"; do
    sips -z "$size" "$size" "$MASTER_PNG" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$MASTER_PNG" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
  rm -rf "$ICONSET_DIR" "$MASTER_PNG"
  echo "Bundled AppIcon.icns (from $(basename "$APP_ICON_SRC"))"
else
  echo "WARNING: AppIcon.png / ikonka.png not found — Finder/Dock will show the placeholder icon." >&2
fi

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

# Premium gates: enforced on release builds. Set ENFORCE_LICENSE=0 for local beta.
LICENSE_PLIST=""
if [[ "${ENFORCE_LICENSE:-1}" == "1" ]]; then
  LICENSE_PLIST="$(cat <<LICENSE
  <key>NFEnforceLicense</key>
  <true/>
LICENSE
)"
fi

POLAR_PLIST=""
if [[ -n "${POLAR_ORGANIZATION_ID:-}" ]]; then
  POLAR_PLIST="$(cat <<POLAR
  <key>PolarOrganizationID</key>
  <string>${POLAR_ORGANIZATION_ID}</string>
POLAR
)"
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
  <key>CFBundleLocalizations</key>
  <array>
    <string>en</string>
    <string>pl</string>
    <string>de</string>
    <string>it</string>
    <string>es</string>
  </array>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
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
${LICENSE_PLIST}
${POLAR_PLIST}
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
  <key>NSContactsUsageDescription</key>
  <string>NotchFlow shows the contact photo for incoming phone calls in the notch.</string>
  <key>NSCameraUsageDescription</key>
  <string>NotchFlow shows a live camera preview in the Camera Mirror module.</string>
  <key>NFNotificationIconResolver</key>
  <string>v35</string>
</dict>
</plist>
PLIST

# Sign with a stable identity so TCC grants (Accessibility) survive rebuilds.
# Ad-hoc/linker signatures change CDHash on every build, silently revoking AX trust.
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-Apple Development}"
if security find-identity -v -p codesigning | grep -q "$CODESIGN_IDENTITY"; then
  codesign --force --sign "$CODESIGN_IDENTITY" "$APP_DIR"
  echo "Signed with: $CODESIGN_IDENTITY"
else
  echo "WARNING: codesign identity '$CODESIGN_IDENTITY' not found — ad-hoc signature; Accessibility grant will break on each rebuild." >&2
fi

echo "Packaged: $APP_DIR"
