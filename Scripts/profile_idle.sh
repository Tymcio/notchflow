#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

Scripts/package_app.sh

PID=$(pgrep -x NotchFlow || true)
if [[ -n "$PID" ]]; then
  echo "Sampling NotchFlow PID $PID for 5 seconds..."
  sample "$PID" 5 -file /tmp/notchflow-idle-sample.txt
  echo "Sample written to /tmp/notchflow-idle-sample.txt"
else
  echo "NotchFlow is not running. Launch with Scripts/compile_and_run.sh first."
  exit 1
fi

echo "Performance checklist: docs/performance.md"
