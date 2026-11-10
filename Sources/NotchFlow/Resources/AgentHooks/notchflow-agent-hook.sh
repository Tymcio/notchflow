#!/bin/bash
# NotchFlow Agents bridge — Claude Code, Codex, Copilot CLI, Qwen Code, Gemini CLI, OpenCode,
# Kilo Code, Crush, Droid, Cursor, Grok Build (and generic CLIs via NOTCHFLOW_AGENT).
set -euo pipefail
# Always exit 0. A failing hook must never block the agent: Copilot CLI denies the tool when a
# preToolUse hook fails, and Codex / Claude Code treat exit 2 as "block".
trap 'exit 0' EXIT

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

# Sends the bearer token on curl's stdin (`-H @-`), never on its command line, so it
# does not show up in `ps` while the permission poll below runs. `printf` is a bash
# builtin, so the token is never in any process's argv. Needs curl >= 7.55 (macOS 14+).
auth_header() {
  printf 'Authorization: Bearer %s\n' "$TOKEN"
}

PARSED="$(
  printf '%s' "$INPUT" | FORCED_EVENT="$FORCED_EVENT" AGENT_HINT="$AGENT" /usr/bin/python3 -c '
import json, os, sys, hashlib
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}

forced = os.environ.get("FORCED_EVENT") or ""
hint = (os.environ.get("AGENT_HINT") or "").strip().lower()
event = forced or d.get("hook_event_name") or d.get("hookEventName") or d.get("event") or d.get("hook_event") or "update"

# Detect agent from payload shape when env hint is missing.
agent = hint
if os.environ.get("GROK_SESSION_ID") or os.environ.get("GROK_HOOK_EVENT"):
    agent = "grok"
elif not agent:
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
    d.get("conversation_id") or d.get("session_id") or d.get("sessionId")
    or os.environ.get("GROK_SESSION_ID") or ""
)
finish_all = False
ev_l = str(event).lower()
if not session:
    if ev_l in {"stop", "sessionend", "session_end", "stopfailure"}:
        finish_all = True
    else:
        session = d.get("generation_id") or ""
        if not session:
            raw = json.dumps(d, sort_keys=True, default=str)[:500]
            session = hashlib.sha1(f"{agent}:{event}:{raw}".encode()).hexdigest()[:12]

# Agents NotchFlow maps here (event name -> NotchFlow event). Claude Code, Cursor and Grok
# Build keep the shell mapping further down.
AGENT_EVENTS = {
    "codex": {
        "sessionstart": "session.started", "userpromptsubmit": "session.started",
        "pretooluse": "tool", "posttooluse": "tool", "permissionrequest": "permission",
        "stop": "done", "sessionend": "done",
    },
    "qwen": {
        "sessionstart": "session.started", "userpromptsubmit": "session.started",
        "pretooluse": "tool", "posttooluse": "tool", "permissionrequest": "permission",
        "notification": "notification", "stop": "done", "sessionend": "done",
    },
    "copilot": {
        "sessionstart": "session.started", "userpromptsubmitted": "session.started",
        "pretooluse": "tool", "posttooluse": "tool", "permissionrequest": "permission",
        "notification": "notification", "agentstop": "done", "sessionend": "done",
    },
    "gemini": {
        "sessionstart": "session.started", "beforeagent": "session.started",
        "beforetool": "tool", "aftertool": "tool", "notification": "notification",
        "afteragent": "done", "sessionend": "done",
    },
    "opencode": {
        "session.busy": "session.started", "tool.execute.before": "tool",
        "permission.asked": "attention", "permission.replied": "progress",
        "session.idle": "done", "session.error": "error",
    },
    "crush": {
        "sessionstart": "session.started", "turnstart": "session.started",
        "pretooluse": "tool", "posttooluse": "tool", "permissionrequest": "attention",
        "permissionresult": "progress", "turnend": "done", "stopfailure": "error",
        "sessionend": "done",
    },
    "droid": {
        "sessionstart": "session.started", "userpromptsubmit": "session.started",
        "pretooluse": "tool", "posttooluse": "tool", "notification": "notification",
        "stop": "done", "sessionend": "done",
    },
}
AGENT_EVENTS["kilo"] = AGENT_EVENTS["opencode"]

nf_event = ""
if agent in AGENT_EVENTS:
    nf_event = AGENT_EVENTS[agent].get(ev_l, "progress")
    note = str(d.get("notification_type") or d.get("notificationType") or "").lower()
    # Monitor-only consent moments: the notch pulses, the user answers in the agent.
    if ev_l == "notification" and (
        (agent == "gemini" and note == "toolpermission")
        or (agent == "droid" and note == "permission_prompt")
    ):
        nf_event = "attention"
    elif agent == "droid" and ev_l == "notification" and note == "idle_prompt":
        # Droid sends this (instead of Stop) when the user cancels a turn.
        nf_event = "done"
    if nf_event in ("done", "error") and not d.get("conversation_id") and not (
        d.get("session_id") or d.get("sessionId")
    ):
        finish_all = True
        session = ""

tool = d.get("tool_name") or d.get("toolName") or d.get("tool_type") or d.get("tool") or ""
cwd = d.get("cwd") or d.get("workspaceRoot") or os.environ.get("GROK_WORKSPACE_ROOT") or ""
wr = d.get("workspace_roots")
if not cwd and isinstance(wr, list) and wr:
    cwd = wr[0]

def as_dict(value):
    if isinstance(value, dict):
        return value
    if isinstance(value, str) and value.strip().startswith("{"):
        try:
            parsed = json.loads(value)
        except Exception:
            return {}
        return parsed if isinstance(parsed, dict) else {}
    return {}

# Claude-style tool_input; Copilot CLI sends toolArgs / toolInput (sometimes as a JSON string).
ti = as_dict(d.get("tool_input")) or as_dict(d.get("toolArgs")) or as_dict(d.get("toolInput"))
summary = ""
if isinstance(ti, dict):
    summary = ti.get("command") or ti.get("file_path") or ti.get("filePath") or ti.get("path") or ""
if not summary:
    summary = d.get("command") or d.get("prompt") or d.get("text") or ""
if nf_event in ("notification", "attention", "error"):
    summary = summary or d.get("message") or ""
elif nf_event == "session.started":
    # A typed prompt is not shown in the notch (screen sharing); "Working..." is enough.
    summary = ""

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
    "nfEvent": str(nf_event),
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
NF_OVERRIDE="$(printf '%s' "$PARSED" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("nfEvent") or "")')"

# Agents whose permission prompts can be answered from the notch (Allow / Deny).
answers_in_notch() {
  case "$AGENT" in
    claude|codex|qwen|copilot) return 0 ;;
    *) return 1 ;;
  esac
}

PERMISSION_ID=""
NF_EVENT="progress"
if [[ -n "$NF_OVERRIDE" ]]; then
  # Codex, Copilot CLI, Qwen Code, Gemini CLI, OpenCode, Kilo Code, Crush, Droid (mapped above).
  NF_EVENT="$NF_OVERRIDE"
  if [[ "$NF_EVENT" == "permission" ]] && ! answers_in_notch; then
    NF_EVENT="attention"
  fi
  if [[ "$NF_EVENT" == "permission" ]]; then
    PERMISSION_ID="$(/usr/bin/uuidgen)"
    if [[ -z "$TOOL_NAME" ]]; then
      TOOL_NAME="Permission"
    fi
  fi
else
case "$EVENT_NAME" in
  PermissionRequest)
    # Claude Code only — Cursor must never block here.
    if [[ "$AGENT" == "cursor" || "$AGENT" == "grok" ]]; then
      NF_EVENT="tool"
    elif ! answers_in_notch; then
      # Other CLIs wired by hand: the notch pulses, the prompt stays in the agent.
      NF_EVENT="attention"
    else
      NF_EVENT="permission"
      # Unique per request: two prompts in the same second must never share an id,
      # or one Allow in the notch would approve both (including one the user never saw).
      PERMISSION_ID="$(/usr/bin/uuidgen)"
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
  SessionEnd|sessionEnd|Stop|stop|StopFailure) NF_EVENT="done" ;;
  # Claude Code sends Notification right after PermissionRequest ("needs your permission")
  # and when idle. It is not progress: it must not clear a prompt waiting in the notch.
  Notification) NF_EVENT="notification" ;;
  PostToolUse|postToolUse|afterShellExecution|afterFileEdit) NF_EVENT="tool" ;;
  *) NF_EVENT="progress" ;;
esac
fi

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
  grok) TITLE="Grok Build" ;;
  grokbot) TITLE="Grok Bot" ;;
  copilot) TITLE="Copilot CLI" ;;
  qwen) TITLE="Qwen Code" ;;
  kilo) TITLE="Kilo Code" ;;
  crush) TITLE="Crush" ;;
  droid) TITLE="Droid" ;;
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

# The app the agent runs in (Terminal, iTerm, VS Code, the Claude app…): macOS passes the
# launching app's bundle id down to child processes. Used when you click to jump back.
BUNDLE="${__CFBundleIdentifier:-}"
case "$AGENT" in
  cursor) BUNDLE="com.todesktop.230313mzl4w4u92" ;;
esac
if [[ "$NF_EVENT" == "notification" ]]; then
  DETAIL=""
fi

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

POSTED=1
auth_header | /usr/bin/curl -sS -f --max-time 5 -X POST "${BASE}/v1/agents/events" \
  -H @- \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" >/dev/null 2>&1 || POSTED=0

# Grok Build keeps its own prompts. Never wait, and never print an allow/deny decision.
if [[ "$AGENT" == "grok" ]]; then
  exit 0
fi

# Cursor (and any before* observe hooks): never block the agent loop, and never decide.
# A "permission" field would override Cursor's own approval flow ("allow" skips the
# Skip/Run prompt for every command). Answer with no decision so Cursor applies its
# allowlist and asks the user exactly as it would without NotchFlow.
if [[ "$AGENT" == "cursor" ]]; then
  case "$EVENT_NAME" in
    beforeShellExecution|beforeMCPExecution|preToolUse)
      printf '%s\n' '{"continue":true}'
      exit 0
      ;;
  esac
  exit 0
fi

if [[ "$NF_EVENT" != "permission" || -z "$PERMISSION_ID" ]] || ! answers_in_notch; then
  exit 0
fi

# NotchFlow is not running (or the Agents addon is locked): nobody can answer in the notch,
# so leave the prompt to the agent right away instead of waiting.
if [[ "$POSTED" != "1" ]]; then
  exit 0
fi

# Prints the agent's answer to its PermissionRequest hook.
print_decision() {
  case "$AGENT:$1" in
    copilot:allow) printf '%s\n' '{"behavior":"allow"}' ;;
    copilot:deny) printf '%s\n' '{"behavior":"deny","message":"Denied in NotchFlow"}' ;;
    codex:deny|qwen:deny)
      printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Denied in NotchFlow"}}}'
      ;;
    *:allow)
      printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
      ;;
    *:deny)
      printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny"}}}'
      ;;
  esac
}

FAILURES=0
for _ in $(seq 1 600); do
  if RESP="$(auth_header | /usr/bin/curl -sS -f --max-time 5 "${BASE}/v1/agents/permission/${PERMISSION_ID}" \
    -H @- 2>/dev/null)"; then
    FAILURES=0
  else
    RESP=""
    FAILURES=$((FAILURES + 1))
    # NotchFlow quit while the prompt was waiting: hand it back to the agent.
    if [[ "$FAILURES" -ge 5 ]]; then
      exit 0
    fi
  fi
  DECISION="$(printf '%s' "$RESP" | /usr/bin/python3 -c 'import json,sys
try:
  print(json.load(sys.stdin).get("decision") or "")
except Exception:
  print("")' 2>/dev/null || true)"
  if [[ "$DECISION" == "allow" || "$DECISION" == "deny" ]]; then
    print_decision "$DECISION"
    exit 0
  fi
  sleep 1
done

exit 0
