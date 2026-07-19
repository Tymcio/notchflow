# NotchFlow Agents addon

One-time **€14.90** Polar product for monitoring popular AI coding agents in the notch.

Supported: **Claude Code**, **Codex**, **Cursor**, **OpenCode**, **Gemini CLI**, **Kimi Code**, **DeepSeek**.

## Setup

1. Buy / activate an Agents key (`NOTCHFLOW_AGENTS_…`) in **Settings → License**.
2. Enable **Local API** (Settings → Integrations) — hooks talk to `127.0.0.1`.
3. Open the **Agents** tab in the island → **Enable Agents**, or use **Install / refresh agent hooks** in Integrations.

That installs:

- `~/Library/Application Support/NotchFlow/Agents/notchflow-agent-hook.sh`
- Claude Code hooks in `~/.claude/settings.json`
- Per-agent notes for Codex / Cursor / OpenCode / Gemini / Kimi / DeepSeek

## Claude Code

Permission prompts are forwarded to the island. **Allow** / **Deny** answers the hook (up to ~10 minutes wait). Other events (`SessionStart`, `Stop`, `Notification`, `PostToolUse`) update session status.

## Other agents

Wire each tool’s notify/hook command to the same script (`NOTCHFLOW_AGENT=codex …`), or `POST /v1/agents/events` (see [raycast-integration.md](raycast-integration.md)).

## Licensing

Agents is **independent of Premium**. Both keys can be active on the same Mac (activation limit 2 each). See [free-vs-premium.md](free-vs-premium.md) and [polar-setup.md](polar-setup.md).
