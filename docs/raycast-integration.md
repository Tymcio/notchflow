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

| Method | Path | Description | Premium |
|--------|------|-------------|---------|
| GET | `/v1/status` | Playback + premium flag | Free |
| POST | `/v1/media/play-pause` | Toggle playback | Free |
| POST | `/v1/media/next` | Next track | Free |
| POST | `/v1/media/previous` | Previous track | Free |
| GET | `/v1/notes` | List notes | Premium |
| POST | `/v1/notes` | Add note `{"text":"..."}` | Premium |
| GET | `/v1/clipboard` | Clipboard history | Premium |
| POST | `/v1/island/show` | Expand notch island | Free |
| POST | `/v1/mirror/toggle` | Toggle camera mirror | Premium |

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
curl -s -H "Authorization: Bearer $TOKEN" -X POST "$BASE/v1/media/play-pause"
```

## Security

- API binds to loopback only (`127.0.0.1`).
- Token stored in macOS Keychain.
- Disable Local API in Settings when not needed.
