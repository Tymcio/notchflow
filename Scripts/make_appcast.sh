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

SPARKLE_TOOLS_VERSION="${SPARKLE_TOOLS_VERSION:-2.9.4}"

resolve_sign_update() {
  local candidates=(
    # If Sparkle embeds tools in app bundle (sometimes it doesn't)
    "$ROOT_DIR/build/${APP_NAME}.app/Contents/Frameworks/Sparkle.framework/Resources/sign_update"
    "$ROOT_DIR/build/${APP_NAME}.app/Contents/Frameworks/Sparkle.framework/Versions/A/Resources/sign_update"
    "$ROOT_DIR/build/${APP_NAME}.app/Contents/Frameworks/Sparkle.framework/Versions/B/Resources/sign_update"

    # SwiftPM checkout locations (CI/local dev)
    "$ROOT_DIR/.build/checkouts/Sparkle/bin/sign_update"
    "$ROOT_DIR/.build/checkouts/Sparkle/Sparkle/bin/sign_update"

    # Downloaded tools fallback (this script will populate)
    "$ROOT_DIR/build/sparkle-tools/bin/sign_update"
  )

  for c in "${candidates[@]}"; do
    if [[ -x "$c" ]]; then
      echo "$c"
      return 0
    fi
  done

  return 1
}

download_sparkle_tools() {
  local tools_dir="$ROOT_DIR/build/sparkle-tools"
  local zip_path="$ROOT_DIR/build/Sparkle-for-SPM.zip"
  local url="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_TOOLS_VERSION}/Sparkle-for-Swift-Package-Manager.zip"

  mkdir -p "$tools_dir"
  echo "Downloading Sparkle tools (${SPARKLE_TOOLS_VERSION}) to: $tools_dir"
  curl -fsSL -o "$zip_path" "$url"
  unzip -q -o "$zip_path" -d "$tools_dir"
  rm -f "$zip_path"
}

SIGN_UPDATE="$(resolve_sign_update || true)"
if [[ -z "${SIGN_UPDATE:-}" ]]; then
  download_sparkle_tools
  SIGN_UPDATE="$(resolve_sign_update || true)"
fi

if [[ -z "${SIGN_UPDATE:-}" ]] || [[ ! -x "$SIGN_UPDATE" ]]; then
  echo "Missing Sparkle sign_update tool (searched app bundle, SwiftPM checkout, and downloaded tools)."
  exit 1
fi

if [[ -z "${SPARKLE_PRIVATE_ED_KEY:-}" ]]; then
  echo "Missing SPARKLE_PRIVATE_ED_KEY (required to sign appcast enclosure)."
  exit 1
fi

KEY_FILE="$(mktemp -t notchflow-sparkle.XXXXXX.key)"
chmod 600 "$KEY_FILE"
printf "%s" "$SPARKLE_PRIVATE_ED_KEY" >"$KEY_FILE"

RAW_SIGNATURE="$("$SIGN_UPDATE" --ed-key-file "$KEY_FILE" "$DMG_PATH")"
rm -f "$KEY_FILE"

ED_SIGNATURE="$RAW_SIGNATURE"
# `sign_update` often prints a full XML attribute snippet, e.g.
# sparkle:edSignature="..." length="...". We only want the base64 payload.
if [[ "$RAW_SIGNATURE" =~ sparkle:edSignature=\"([^\"]+)\" ]]; then
  ED_SIGNATURE="${BASH_REMATCH[1]}"
fi

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
