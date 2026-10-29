# NotchFlow Agents addon

One-time **€14.90** Polar product for monitoring popular AI coding agents in the notch.

Supported: **Claude Code**, **Codex**, **Cursor**, **Grok Build**, **Grok Bot**, **OpenCode**, **Gemini CLI**, **Kimi Code**, **DeepSeek**.

## Setup

1. Activate an Agents key in **Settings → License** (or use beta unlock).
2. Open **Settings → Integrations → Agents**.
3. Click **Connect agents (Claude, Cursor, Grok)**.
4. **Fully quit Cursor** (`Cmd+Q`) and open it again. Restart the `grok` CLI so it reloads `~/.grok/hooks/notchflow.json`.
5. Start **Agent Chat** — session status appears in the notch. Grok Bot has no live session; its weekly limit appears in the Agents tab.

Setup lives only in Settings (not in the island Agents tab).

## Cursor vs Claude Code

| | Cursor | Claude Code |
|--|--------|-------------|
| Status in notch | ✓ | ✓ |
| Allow / Deny in notch | — (Cursor keeps its own prompts) | ✓ |
| Config | `~/.cursor/hooks.json` | `~/.claude/settings.json` |

Cursor hooks are **monitor-only** (`sessionStart`, `stop`, `postToolUse`, …). Blocking hooks like `beforeShellExecution` are intentionally not installed — they caused Cursor to hang waiting for NotchFlow while showing no in-app permission UI.

Grok Build hooks are monitor-only too (`SessionStart`, `PostToolUse`, `Stop`, `SessionEnd`, `StopFailure`, `Notification` in `~/.grok/hooks/notchflow.json`). Allow and Deny stay in the terminal. Grok Bot has no hooks.

## Usage limits

With the Agents addon, the island can show **remaining 5-hour and 7-day quota** for Claude Code and Codex — the same windows `/usage` reports. Cursor shows the included allowance already on this Mac: two monthly pools on a legacy plan (Cursor models and third-party models), or one weekly pool on The X Subscription. Grok Build and Grok Bot each show one weekly remaining bar (the shared Grok Build credit pool, and Grok Bot’s included weekly usage).

- Reuses the login already on this Mac (Claude Code Keychain or `~/.claude/.credentials.json`, Claude Desktop’s local login, `~/.codex/auth.json`, Cursor’s local login, `~/.grok/auth.json`, and the Grok Bot app login). Claude Desktop and Grok Build refresh tokens are never rotated. When a Cursor or Grok Bot access token is rejected, NotchFlow refreshes it into its own cache and does not write that login back into Cursor or the Grok Bot app.
- Asks Anthropic, OpenAI, Cursor, and xAI usage endpoints only. Tokens are not sent to NotchFlow servers.
- Toggle in **Settings → Integrations**. Off = no usage network calls.
- Idle wing shows the tighter window as a remaining percentage while that agent is running. Grok Bot never starts a session, so its bar stays in the Agents tab.

## Other agents

Wire notify/hook commands to the same script with `NOTCHFLOW_AGENT=…`, or `POST /v1/agents/events` (see [raycast-integration.md](raycast-integration.md)).

## Licensing

Agents is **independent of Premium**. See [free-vs-premium.md](free-vs-premium.md) and [polar-setup.md](polar-setup.md).
