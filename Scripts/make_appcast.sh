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
      <enclosure url="https://notchflow.eu/downloads/${APP_NAME}-${MARKETING_VERSION}.dmg" sparkle:version="${BUILD_NUMBER}" sparkle:shortVersionString="${MARKETING_VERSION}" length="${LENGTH}" type="application/octet-stream" sparkle:edSignature="REPLACE_WITH_ED_SIGNATURE"/>
    </item>
  </channel>
</rss>
XML

echo "Appcast written to $APPCAST_PATH"
echo "SHA256: $SHA256"
