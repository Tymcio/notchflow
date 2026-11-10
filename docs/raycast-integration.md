# NotchFlow Raycast Integration

NotchFlow exposes a **local-only HTTP API** on `127.0.0.1` for Raycast and other automation tools.

## Setup

1. Launch NotchFlow and open **Settings → Integrations**.
2. Enable **Local API (Raycast)**.
3. Copy the **API token** (Base URL is read automatically from `api.json` by the Raycast extension).

### Raycast extension

Install from source:

```bash
cd integrations/raycast/notchflow
npm install
npm run dev
```

In Raycast extension preferences set:

| Preference | Value |
|------------|-------|
| Base URL | Optional — auto-read from `api.json` |
| API Token | Token from NotchFlow Settings |

NotchFlow uses a **stable default port `47821`** on loopback. The port is persisted in `api.json` and reused across restarts.

## Endpoints

All requests require header:

```
Authorization: Bearer <token>
```

| Method | Path | Description | Gate |
|--------|------|-------------|------|
| GET | `/v1/status` | Playback + premium flag | Free |
| POST | `/v1/media/play-pause` | Toggle playback | Free |
| POST | `/v1/media/next` | Next track | Free |
| POST | `/v1/media/previous` | Previous track | Free |
| GET | `/v1/notes` | List notes | Premium |
| POST | `/v1/notes` | Add note `{"text":"..."}` | Premium |
| GET | `/v1/clipboard` | Clipboard history | Premium |
| POST | `/v1/island/show` | Expand notch island | Free |
| POST | `/v1/mirror/toggle` | Toggle camera mirror | Premium |
| POST | `/v1/agents/events` | Ingest agent session event | Agents addon |
| GET | `/v1/agents/sessions` | List agent sessions | Agents addon |
| GET | `/v1/agents/permission/<id>` | Poll Allow/Deny decision | Agents addon |
| POST | `/v1/agents/permission/<id>` | Set decision `{"decision":"allow\|deny"}` | Agents addon |
| GET | `/v1/agents/question/<id>` | Poll question answer | Agents addon |

### Agents event payload

```json
{
  "agent": "claude",
  "event": "permission",
  "sessionId": "abc",
  "title": "fix auth bug",
  "toolName": "Bash",
  "summary": "npm test",
  "permissionId": "p1",
  "cwd": "/path/to/project"
}
```

`agent` values: `claude`, `codex`, `cursor`, `opencode`, `gemini`, `kimi`, `deepseek`.
`event` values: `session.started`, `tool`, `permission`, `question`, `done`, `error`, `clear`.

## URL scheme

Register `notchflow://` deeplinks:

| URL | Action |
|-----|--------|
| `notchflow://play-pause` | Toggle media |
| `notchflow://show-island` | Show island |
| `notchflow://add-note?text=Hello` | Quick note |
| `notchflow://mirror-toggle` | Toggle camera |

## Script Command fallback

Without the Raycast extension:

```bash
TOKEN="$(security find-generic-password -s eu.notchflow.app.api -w 2>/dev/null || true)"
BASE="$(python3 -c 'import json, pathlib; print(json.load(open(pathlib.Path.home()/\"Library/Application Support/NotchFlow/api.json\"))[\"baseURL\"])')"
printf 'Authorization: Bearer %s\n' "$TOKEN" | curl -s -H @- -X POST "$BASE/v1/media/play-pause"
```

Passing the header on stdin (`-H @-`) keeps the token out of the process list; NotchFlow's own agent hook does the same.

## Security

- API binds to loopback only (`127.0.0.1`).
- Token stored in macOS Keychain.
- Requests from web pages are refused: any request with an `Origin` header, or with a `Host` other than `127.0.0.1`, `localhost` or `[::1]` (optionally with NotchFlow's port), gets `403`.
- Bodies must use `Content-Length` (no chunked encoding) and the whole request is capped at 1 MB (`413`). A client has 5 seconds to send its request; at most 16 connections are served at once.
- `POST` endpoints answer `400` when the JSON body is missing or invalid.
- Disable Local API in Settings when not needed.
