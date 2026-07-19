#!/bin/bash
set -euo pipefail

AGENT="${NOTCHFLOW_AGENT:-claude}"
API_JSON="${HOME}/Library/Application Support/NotchFlow/api.json"
TOKEN_FILE="${HOME}/Library/Application Support/NotchFlow/api-token"
INPUT="$(cat || true)"

if [[ ! -f "$API_JSON" || ! -f "$TOKEN_FILE" ]]; then
  exit 0
fi

PORT="$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["port"])' "$API_JSON" 2>/dev/null || true)"
TOKEN="$(/bin/cat "$TOKEN_FILE" 2>/dev/null || true)"
if [[ -z "${PORT:-}" || -z "${TOKEN:-}" ]]; then
  exit 0
fi

BASE="http://127.0.0.1:${PORT}"

EVENT_NAME="$(printf '%s' "$INPUT" | /usr/bin/python3 -c 'import json,sys
try:
  d=json.load(sys.stdin)
except Exception:
  d={}
print(d.get("hook_event_name") or d.get("event") or "update")' 2>/dev/null || echo update)"

SESSION_ID="$(printf '%s' "$INPUT" | /usr/bin/python3 -c 'import json,sys
try:
  d=json.load(sys.stdin)
except Exception:
  d={}
print(d.get("session_id") or d.get("sessionId") or "unknown")' 2>/dev/null || echo unknown)"

TOOL_NAME="$(printf '%s' "$INPUT" | /usr/bin/python3 -c 'import json,sys
try:
  d=json.load(sys.stdin)
except Exception:
  d={}
print(d.get("tool_name") or d.get("toolName") or "")' 2>/dev/null || true)"

CWD="$(printf '%s' "$INPUT" | /usr/bin/python3 -c 'import json,sys
try:
  d=json.load(sys.stdin)
except Exception:
  d={}
print(d.get("cwd") or "")' 2>/dev/null || true)"

SUMMARY="$(printf '%s' "$INPUT" | /usr/bin/python3 -c 'import json,sys
try:
  d=json.load(sys.stdin)
except Exception:
  d={}
ti=d.get("tool_input") or {}
if isinstance(ti, dict):
  print(ti.get("command") or ti.get("file_path") or ti.get("path") or "")
else:
  print("")' 2>/dev/null || true)"

PERMISSION_ID=""
NF_EVENT="progress"
case "$EVENT_NAME" in
  PermissionRequest)
    NF_EVENT="permission"
    PERMISSION_ID="${SESSION_ID}-$(date +%s)"
    ;;
  SessionStart) NF_EVENT="session.started" ;;
  Stop) NF_EVENT="done" ;;
  Notification) NF_EVENT="progress" ;;
  PostToolUse) NF_EVENT="tool" ;;
  *) NF_EVENT="progress" ;;
esac

PAYLOAD=$(AGENT="$AGENT" NF_EVENT="$NF_EVENT" SESSION_ID="$SESSION_ID" TOOL_NAME="$TOOL_NAME" SUMMARY="$SUMMARY" CWD="$CWD" PERMISSION_ID="$PERMISSION_ID" EVENT_NAME="$EVENT_NAME" /usr/bin/python3 - <<'PY'
import json, os
print(json.dumps({
  "agent": os.environ.get("AGENT", "claude"),
  "event": os.environ.get("NF_EVENT", "progress"),
  "sessionId": os.environ.get("SESSION_ID", "unknown"),
  "title": os.environ.get("TOOL_NAME") or os.environ.get("AGENT", "claude"),
  "detail": os.environ.get("SUMMARY") or os.environ.get("EVENT_NAME", ""),
  "toolName": os.environ.get("TOOL_NAME", ""),
  "summary": os.environ.get("SUMMARY", ""),
  "cwd": os.environ.get("CWD", ""),
  "permissionId": os.environ.get("PERMISSION_ID", ""),
}))
PY
)

/usr/bin/curl -sS -X POST "${BASE}/v1/agents/events" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" >/dev/null 2>&1 || true

if [[ "$NF_EVENT" != "permission" || -z "$PERMISSION_ID" ]]; then
  exit 0
fi

for _ in $(seq 1 600); do
  RESP="$(/usr/bin/curl -sS "${BASE}/v1/agents/permission/${PERMISSION_ID}" \
    -H "Authorization: Bearer ${TOKEN}" 2>/dev/null || true)"
  DECISION="$(printf '%s' "$RESP" | /usr/bin/python3 -c 'import json,sys
try:
  print(json.load(sys.stdin).get("decision") or "")
except Exception:
  print("")' 2>/dev/null || true)"
  if [[ "$DECISION" == "allow" ]]; then
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
    exit 0
  fi
  if [[ "$DECISION" == "deny" ]]; then
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny"}}}'
    exit 0
  fi
  sleep 1
done

exit 0
