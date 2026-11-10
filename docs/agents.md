# NotchFlow Agents addon

One-time **€14.90** Polar product for monitoring popular AI coding agents in the notch.

Supported: **Claude Code**, **Codex**, **Copilot CLI**, **Qwen Code**, **Gemini CLI**, **OpenCode**, **Kilo Code**, **Crush**, **Droid**, **Cursor**, **Grok Build**, **Grok Bot** (usage only), plus **Kimi Code** and **DeepSeek** wired by hand.

## Setup

1. Activate an Agents key in **Settings → License** (or use beta unlock).
2. Open **Settings → Integrations → Agents**. NotchFlow lists the agents that look installed on this Mac: their config folder exists, or their binary is in `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, `~/.npm-global/bin` or `~/.bun/bin`. It only checks that files exist; it never runs an agent.
3. Leave on the agents you want (all detected agents are on by default) and click **Connect agents**. This also turns on the Local API.
4. **Codex only:** run `/hooks` in Codex once and trust the NotchFlow hook. Codex skips new or changed hooks until you do (the trust is stored in `~/.codex/config.toml`, which NotchFlow never edits).
5. Restart agents that are already running so they load the hooks: fully quit Cursor (`Cmd+Q`), restart the `grok`, `codex`, `copilot`, `qwen`, `gemini`, `opencode`, `kilo`, `crush` and `droid` CLIs.
6. Work as usual — session status appears in the notch. Grok Bot has no live session; its weekly limit appears in the Agents tab.

**Disconnect** removes only what NotchFlow added: its hook entries (anything that runs `notchflow-agent-hook`), the plugin files it wrote, and its block in `crushrc`. Everything else in those files stays.

Setup lives only in Settings (not in the island Agents tab).

## What works per agent

| Agent | Status in notch | Allow / Deny in notch | What NotchFlow writes | Events |
|--|--|--|--|--|
| Claude Code | ✓ | ✓ | `~/.claude/settings.json` (merged) | SessionStart, PostToolUse, PermissionRequest, Notification, Stop |
| Codex | ✓ | ✓ (after `/hooks` trust) | `~/.codex/hooks.json` (merged) | SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, PermissionRequest, Stop |
| Copilot CLI | ✓ | ✓ | `~/.copilot/hooks/notchflow.json` (own file) | sessionStart, userPromptSubmitted, preToolUse, permissionRequest, notification, agentStop, sessionEnd |
| Qwen Code | ✓ | ✓ | `~/.qwen/settings.json` (merged) | SessionStart, UserPromptSubmit, PreToolUse, PermissionRequest, Notification, Stop |
| Gemini CLI | ✓ | — (pulse + jump) | `~/.gemini/settings.json` (merged `hooks` key) | SessionStart, BeforeAgent, BeforeTool, AfterTool, Notification, AfterAgent, SessionEnd |
| OpenCode | ✓ | — (pulse + jump) | `~/.config/opencode/plugins/notchflow.js` (own file) | session.status, tool.execute.before, permission.asked / replied, session.idle, session.error |
| Kilo Code | ✓ | — (pulse + jump) | `~/.config/kilo/plugin/notchflow.js` (own file) | same as OpenCode |
| Crush | ✓ | — (pulse + jump) | block in `~/.config/crush/crushrc` | SessionStart, TurnStart, PreToolUse, PermissionRequest, PermissionResult, TurnEnd, StopFailure |
| Droid | ✓ | — (pulse + jump) | `~/.factory/hooks.json` (merged) | SessionStart, UserPromptSubmit, PreToolUse, Notification, Stop |
| Cursor | ✓ | — (keeps Skip/Run) | `~/.cursor/hooks.json` (merged) | sessionStart, sessionEnd, stop, beforeShell/MCPExecution, afterShellExecution, postToolUse, afterFileEdit |
| Grok Build | ✓ | — (prompts stay in the terminal) | `~/.grok/hooks/notchflow.json` (own file) | SessionStart, PostToolUse, Stop, SessionEnd, StopFailure, Notification |

"Pulse + jump": when the agent asks for permission, the notch pulses and offers to jump back to the agent; you answer in the agent. NotchFlow never prints a decision for these agents, so their own permission rules apply exactly as without NotchFlow.

Notes per agent:

- **Codex** runs hook commands through your login shell. Permission prompts wait up to 600 s for the notch, then Codex shows its own prompt.
- **Copilot CLI** treats a failing `preToolUse` hook as *deny* (fail closed). NotchFlow's hook therefore always exits 0 — also when NotchFlow is not running, the network call fails or the payload cannot be parsed — and the command in `notchflow.json` ends with `|| true` in case the script itself is missing. A hook that times out lets the tool through. Copilot also reads hooks from `$COPILOT_HOME/hooks` when that is set; NotchFlow writes to `~/.copilot/hooks`.
- **Qwen Code** uses Claude Code's hook format. `Notification` never clears a prompt waiting in the notch.
- **Gemini CLI** timeouts are milliseconds (NotchFlow uses 5000). A `Notification` with `notification_type: ToolPermission` pulses the notch. Gemini CLI has been succeeded by Antigravity CLI; these hooks work with Gemini CLI.
- **OpenCode / Kilo Code**: the plugin is a small ES module that starts the hook script in the background (fire-and-forget) and never throws into the agent. It supports OpenCode's V1 (`server`, OpenCode 1.18.29 or newer) and V2 (`setup`) plugin APIs, and Kilo Code. NotchFlow only replaces or deletes a `notchflow.js` that starts with `// Installed by NotchFlow`.
- **Crush** hooks are lines in `crushrc` between `# >>> NotchFlow agent hooks …` and `# <<< NotchFlow agent hooks <<<`. If you set `XDG_CONFIG_HOME`, Crush reads its global `crushrc` from there; NotchFlow writes `~/.config/crush/crushrc`.
- **Droid** reads `~/.factory/hooks.json` (events at the top level). Only when that file is missing does it read a `hooks` key in `~/.factory/settings.json`; if you keep hooks there, NotchFlow adds its entries to settings.json instead of creating hooks.json (which would hide yours). A `Notification` with `permission_prompt` pulses the notch.
- **Cursor** hooks are monitor-only. Blocking hooks like `preToolUse` are intentionally not installed — they caused Cursor to hang waiting for NotchFlow while showing no in-app permission UI.
- **T3 Code** (untested): it drives Claude Code, Codex and OpenCode underneath, so their hooks still report to NotchFlow when those agents are connected. Jumping back goes to the app the agent runs in.

**How config files are edited.** NotchFlow merges its entries into other tools' files without disturbing the rest: a symlinked file stays a symlink (the real file is updated), its permissions are kept, and the first time NotchFlow changes a file it saves the original next to it as `<file>.notchflow-backup`. If a file exists but is not a JSON object (or does not parse — for example a `settings.json` with comments), NotchFlow stops with an error and leaves it untouched. Re-running Connect replaces NotchFlow's old entries instead of adding duplicates.

**When NotchFlow is not running**, every hook exits at once with no answer, so agents behave as if NotchFlow were not installed. If NotchFlow quits while a prompt waits in the notch, the hook hands the prompt back to the agent within a few seconds.

## Usage limits

With the Agents addon, the island can show **remaining 5-hour and 7-day quota** for Claude Code and Codex — the same windows `/usage` reports. Cursor shows the included allowance already on this Mac: two monthly pools on a legacy plan (Cursor models and third-party models), or one weekly pool on The X Subscription. Grok Build and Grok Bot each show one weekly remaining bar (the shared Grok Build credit pool, and Grok Bot’s included weekly usage).

- Reuses the login already on this Mac (Claude Code Keychain or `~/.claude/.credentials.json`, Claude Desktop’s local login, `~/.codex/auth.json`, Cursor’s local login, `~/.grok/auth.json`, and the Grok Bot app login). Claude Desktop and Grok Build refresh tokens are never rotated. When a Cursor or Grok Bot access token is rejected, NotchFlow refreshes it and keeps the new pair in memory until it quits; it never writes another app’s decrypted tokens to disk and does not write that login back into Cursor or the Grok Bot app. Files older builds left behind (`cursor-oauth.json`, `grokbot-oauth.json` in `~/Library/Application Support/NotchFlow/Agents`) are deleted at launch.
- Asks Anthropic, OpenAI, Cursor, and xAI usage endpoints only. Tokens are not sent to NotchFlow servers.
- Keychain prompts: Claude Desktop, Cursor and Grok Bot encrypt their local data with a key stored in the Keychain as “Claude Safe Storage”, “Cursor Safe Storage” and “Grok Bot Safe Storage”. Granting NotchFlow access (especially **Always Allow**) gives it that whole key — it could decrypt everything that app keeps encrypted on this Mac, not only the login. NotchFlow uses it only to read the login for usage meters. Settings → Integrations says this next to the usage toggle.
- Toggle in **Settings → Integrations**. Off = no usage network calls.
- Idle wing shows the tighter window as a remaining percentage while that agent is running. Grok Bot never starts a session, so its bar stays in the Agents tab.
- No usage meters for Copilot CLI, Gemini CLI, Qwen Code, OpenCode, Kilo Code, Crush or Droid: their quota APIs are undocumented, so NotchFlow does not call them.

## Other agents

Kimi Code, DeepSeek and other CLIs: run the hook script with `NOTCHFLOW_AGENT=<name>` (and optionally `NOTCHFLOW_HOOK_EVENT=<event>`), or `POST /v1/agents/events` (see [raycast-integration.md](raycast-integration.md)). Permission prompts from these agents pulse the notch; only Claude Code, Codex, Copilot CLI and Qwen Code are answered from the notch.

## Licensing

Agents is **independent of Premium**. See [free-vs-premium.md](free-vs-premium.md) and [polar-setup.md](polar-setup.md).
