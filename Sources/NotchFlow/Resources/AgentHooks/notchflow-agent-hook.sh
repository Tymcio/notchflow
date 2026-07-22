#!/bin/bash
# NotchFlow Agents bridge — Claude Code + Cursor (and generic CLIs via NOTCHFLOW_AGENT).
set -euo pipefail

AGENT="${NOTCHFLOW_AGENT:-}"
FORCED_EVENT="${NOTCHFLOW_HOOK_EVENT:-}"
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

PARSED="$(
  printf '%s' "$INPUT" | FORCED_EVENT="$FORCED_EVENT" AGENT_HINT="$AGENT" /usr/bin/python3 -c '
import json, os, sys, hashlib
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}

forced = os.environ.get("FORCED_EVENT") or ""
hint = (os.environ.get("AGENT_HINT") or "").strip().lower()
event = forced or d.get("hook_event_name") or d.get("event") or d.get("hook_event") or "update"

# Detect agent from payload shape when env hint is missing.
agent = hint
if not agent:
    if d.get("conversation_id") or d.get("generation_id") or forced in {
        "sessionStart", "sessionEnd", "beforeShellExecution", "afterShellExecution",
        "preToolUse", "postToolUse", "stop", "afterFileEdit",
    }:
        agent = "cursor"
    elif d.get("hook_event_name"):
        agent = "claude"
    else:
        agent = "claude"

# Prefer stable conversation id. Never key sessions by generation_id alone
# (changes every turn). Cursor `stop` often omits ids — leave empty then.
session = (
    d.get("conversation_id") or d.get("session_id") or d.get("sessionId") or ""
)
finish_all = False
ev_l = str(event).lower()
if not session:
    if ev_l in {"stop", "sessionend", "session_end"}:
        finish_all = True
    else:
        session = d.get("generation_id") or ""
        if not session:
            raw = json.dumps(d, sort_keys=True, default=str)[:500]
            session = hashlib.sha1(f"{agent}:{event}:{raw}".encode()).hexdigest()[:12]

tool = d.get("tool_name") or d.get("toolName") or d.get("tool_type") or d.get("tool") or ""
cwd = d.get("cwd") or ""
wr = d.get("workspace_roots")
if not cwd and isinstance(wr, list) and wr:
    cwd = wr[0]

ti = d.get("tool_input") or {}
summary = ""
if isinstance(ti, dict):
    summary = ti.get("command") or ti.get("file_path") or ti.get("path") or ""
if not summary:
    summary = d.get("command") or d.get("prompt") or d.get("text") or ""

# Cursor keeps its own Skip/Run UI. Flag only high-signal shell moments for a notch pulse
# (no auto-jump — heuristics are noisy). Ignore MCP and unsandboxed shells by themselves.
cmd = str(d.get("command") or summary or "").lower()
needles = (
    "git push", "git commit", "git reset", "git rebase", "sudo ", "rm -rf",
    "rm -r ", "wget ", "ssh ", "kubectl ", "npm publish", "pnpm publish",
    "chmod ", "chown ", "security ", "xcrun notary",
)
wants_attention = False
if ev_l == "beforeshellexecution":
    head = cmd.strip().split("\n")[0]
    # Ignore huge multi-line agent shell blobs (false positives on embedded git/ssh).
    if len(cmd) <= 280:
        wants_attention = any(n in head for n in needles)

print(json.dumps({
    "agent": str(agent),
    "event": str(event),
    "session": str(session),
    "finishAll": bool(finish_all),
    "wantsAttention": bool(wants_attention),
    "tool": str(tool or ""),
    "cwd": str(cwd or ""),
    "summary": str(summary or ""),
}))
'
)"

AGENT="$(printf '%s' "$PARSED" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["agent"])')"
EVENT_NAME="$(printf '%s' "$PARSED" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["event"])')"
SESSION_ID="$(printf '%s' "$PARSED" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("session") or "")')"
FINISH_ALL="$(printf '%s' "$PARSED" | /usr/bin/python3 -c 'import json,sys; print("1" if json.load(sys.stdin).get("finishAll") else "0")')"
WANTS_ATTENTION="$(printf '%s' "$PARSED" | /usr/bin/python3 -c 'import json,sys; print("1" if json.load(sys.stdin).get("wantsAttention") else "0")')"
TOOL_NAME="$(printf '%s' "$PARSED" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["tool"])')"
CWD="$(printf '%s' "$PARSED" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["cwd"])')"
SUMMARY="$(printf '%s' "$PARSED" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["summary"])')"

PERMISSION_ID=""
NF_EVENT="progress"
case "$EVENT_NAME" in
  PermissionRequest)
    # Claude Code only — Cursor must never block here.
    if [[ "$AGENT" == "cursor" ]]; then
      NF_EVENT="tool"
    else
      NF_EVENT="permission"
      PERMISSION_ID="${SESSION_ID}-$(date +%s)"
      if [[ -z "$TOOL_NAME" ]]; then
        TOOL_NAME="Permission"
      fi
    fi
    ;;
  beforeShellExecution|beforeMCPExecution|preToolUse)
    # Cursor: never wait for NotchFlow. Jump-only attention for likely consent prompts.
    if [[ "$AGENT" == "cursor" && "$WANTS_ATTENTION" == "1" ]]; then
      NF_EVENT="attention"
    else
      NF_EVENT="tool"
    fi
    if [[ -z "$TOOL_NAME" ]]; then
      case "$EVENT_NAME" in
        beforeShellExecution) TOOL_NAME="Shell" ;;
        beforeMCPExecution) TOOL_NAME="MCP" ;;
        preToolUse) TOOL_NAME="Tool" ;;
      esac
    fi
    ;;
  SessionStart|sessionStart) NF_EVENT="session.started" ;;
  SessionEnd|sessionEnd|Stop|stop) NF_EVENT="done" ;;
  Notification) NF_EVENT="progress" ;;
  PostToolUse|postToolUse|afterShellExecution|afterFileEdit) NF_EVENT="tool" ;;
  *) NF_EVENT="progress" ;;
esac

# Prefer human title = agent name; keep tool/path in detail (avoids "Write" as headline).
TITLE="$AGENT"
case "$AGENT" in
  cursor) TITLE="Cursor" ;;
  claude) TITLE="Claude Code" ;;
  codex) TITLE="Codex" ;;
  opencode) TITLE="OpenCode" ;;
  gemini) TITLE="Gemini CLI" ;;
  kimi) TITLE="Kimi Code" ;;
  deepseek) TITLE="DeepSeek" ;;
esac

DETAIL="$SUMMARY"
if [[ "$NF_EVENT" == "done" ]]; then
  DETAIL="Done"
  TOOL_NAME=""
elif [[ "$NF_EVENT" == "attention" ]]; then
  if [[ -n "$SUMMARY" ]]; then
    DETAIL="$SUMMARY"
  else
    DETAIL="Needs approval"
  fi
elif [[ -n "$TOOL_NAME" && -n "$SUMMARY" ]]; then
  DETAIL="${TOOL_NAME}: ${SUMMARY}"
elif [[ -n "$TOOL_NAME" ]]; then
  DETAIL="$TOOL_NAME"
elif [[ "$NF_EVENT" == "session.started" ]]; then
  DETAIL="Working…"
elif [[ -n "$EVENT_NAME" ]]; then
  DETAIL="$EVENT_NAME"
fi

BUNDLE=""
case "$AGENT" in
  cursor) BUNDLE="com.todesktop.230313mzl4w4u92" ;;
esac

PAYLOAD=$(
  AGENT="$AGENT" NF_EVENT="$NF_EVENT" SESSION_ID="$SESSION_ID" TOOL_NAME="$TOOL_NAME" \
  SUMMARY="$SUMMARY" DETAIL="$DETAIL" CWD="$CWD" PERMISSION_ID="$PERMISSION_ID" \
  TITLE="$TITLE" BUNDLE="$BUNDLE" FINISH_ALL="$FINISH_ALL" \
  /usr/bin/python3 -c '
import json, os
print(json.dumps({
  "agent": os.environ.get("AGENT", "claude"),
  "event": os.environ.get("NF_EVENT", "progress"),
  "sessionId": os.environ.get("SESSION_ID") or "",
  "finishAll": os.environ.get("FINISH_ALL") == "1",
  "title": os.environ.get("TITLE") or "Agent",
  "detail": os.environ.get("DETAIL") or "",
  "toolName": os.environ.get("TOOL_NAME", ""),
  "summary": os.environ.get("SUMMARY", ""),
  "cwd": os.environ.get("CWD", ""),
  "permissionId": os.environ.get("PERMISSION_ID", ""),
  "terminalBundleId": os.environ.get("BUNDLE", ""),
}))
'
)

/usr/bin/curl -sS -X POST "${BASE}/v1/agents/events" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" >/dev/null 2>&1 || true

# Cursor (and any before* observe hooks): never block the agent loop.
if [[ "$AGENT" == "cursor" ]]; then
  case "$EVENT_NAME" in
    beforeShellExecution|beforeMCPExecution|preToolUse)
      printf '%s\n' '{"continue":true,"permission":"allow"}'
      exit 0
      ;;
  esac
  exit 0
fi

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
