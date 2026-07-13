#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

source version.env

DMG_PATH="$ROOT_DIR/build/${APP_NAME}-${MARKETING_VERSION}.dmg"
APPCAST_PATH="$ROOT_DIR/build/appcast.xml"

if [[ ! -f "$DMG_PATH" ]]; then
  echo "Missing DMG: $DMG_PATH"
  exit 1
fi

SHA256=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')
LENGTH=$(stat -f%z "$DMG_PATH")
PUB_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S +0000")

# GitHub Releases (latest) hosting
GITHUB_OWNER="${GITHUB_OWNER:-Tymcio}"
GITHUB_REPO="${GITHUB_REPO:-notchflow}"
DMG_URL="${DMG_URL:-https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/releases/latest/download/${APP_NAME}.dmg}"

SIGN_UPDATE="$ROOT_DIR/build/${APP_NAME}.app/Contents/Frameworks/Sparkle.framework/Resources/sign_update"
if [[ ! -x "$SIGN_UPDATE" ]]; then
  echo "Missing Sparkle sign_update tool: $SIGN_UPDATE"
  exit 1
fi

if [[ -z "${SPARKLE_PRIVATE_ED_KEY:-}" ]]; then
  echo "Missing SPARKLE_PRIVATE_ED_KEY (required to sign appcast enclosure)."
  exit 1
fi

KEY_FILE="$(mktemp -t notchflow-sparkle.XXXXXX.key)"
chmod 600 "$KEY_FILE"
printf "%s" "$SPARKLE_PRIVATE_ED_KEY" >"$KEY_FILE"

ED_SIGNATURE="$("$SIGN_UPDATE" --ed-key-file "$KEY_FILE" "$DMG_PATH")"
rm -f "$KEY_FILE"

cat > "$APPCAST_PATH" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>NotchFlow</title>
    <item>
      <title>Version ${MARKETING_VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:version>${BUILD_NUMBER}</sparkle:version>
      <sparkle:shortVersionString>${MARKETING_VERSION}</sparkle:shortVersionString>
      <enclosure url="${DMG_URL}" sparkle:version="${BUILD_NUMBER}" sparkle:shortVersionString="${MARKETING_VERSION}" length="${LENGTH}" type="application/octet-stream" sparkle:edSignature="${ED_SIGNATURE}"/>
    </item>
  </channel>
</rss>
XML

echo "Appcast written to $APPCAST_PATH"
echo "SHA256: $SHA256"
