# NotchFlow Agents addon

One-time **€14.90** Polar product for monitoring popular AI coding agents in the notch.

Supported: **Claude Code**, **Codex**, **Cursor**, **OpenCode**, **Gemini CLI**, **Kimi Code**, **DeepSeek**.

## Setup

1. Activate an Agents key in **Settings → License** (or use beta unlock).
2. Open **Settings → Integrations → Agents**.
3. Click **Connect agents (Claude + Cursor)**.
4. **Fully quit Cursor** (`Cmd+Q`) and open it again.
5. Start **Agent Chat** — session status appears in the notch.

Setup lives only in Settings (not in the island Agents tab).

## Cursor vs Claude Code

| | Cursor | Claude Code |
|--|--------|-------------|
| Status in notch | ✓ | ✓ |
| Allow / Deny in notch | — (Cursor keeps its own prompts) | ✓ |
| Config | `~/.cursor/hooks.json` | `~/.claude/settings.json` |

Cursor hooks are **monitor-only** (`sessionStart`, `stop`, `postToolUse`, …). Blocking hooks like `beforeShellExecution` are intentionally not installed — they caused Cursor to hang waiting for NotchFlow while showing no in-app permission UI.

## Usage limits (Claude Code + Codex)

With the Agents addon, the island can show **remaining 5-hour and 7-day quota** for Claude Code and Codex — the same windows `/usage` reports. Cursor shows the included allowance already on this Mac: two monthly pools on a legacy plan (Cursor models and third-party models), or one weekly pool on The X Subscription.

- Reuses the login already on this Mac (Claude Code Keychain or `~/.claude/.credentials.json`, Claude Desktop’s local login, `~/.codex/auth.json`, Cursor’s local login). Desktop and Cursor refresh tokens are never used or rotated.
- Asks Anthropic, OpenAI, and Cursor usage endpoints only. Tokens are not stored by NotchFlow and are not sent to NotchFlow servers.
- Toggle in **Settings → Integrations**. Off = no usage network calls.
- Idle wing shows the tighter window as a remaining percentage while that agent is running.

## Other agents

Wire notify/hook commands to the same script with `NOTCHFLOW_AGENT=…`, or `POST /v1/agents/events` (see [raycast-integration.md](raycast-integration.md)).

## Licensing

Agents is **independent of Premium**. See [free-vs-premium.md](free-vs-premium.md) and [polar-setup.md](polar-setup.md).
