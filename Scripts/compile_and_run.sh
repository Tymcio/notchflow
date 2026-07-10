#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

source version.env

"$ROOT_DIR/Scripts/package_app.sh"

pkill -x "$APP_NAME" 2>/dev/null || true
open "$ROOT_DIR/build/${APP_NAME}.app"
