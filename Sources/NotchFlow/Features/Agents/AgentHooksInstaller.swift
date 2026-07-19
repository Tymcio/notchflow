import Foundation

/// Installs local hook scripts and agent config snippets under Application Support.
enum AgentHooksInstaller {
    private static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchFlow/Agents", isDirectory: true)
    }

    static var hookScriptURL: URL {
        supportDirectory.appendingPathComponent("notchflow-agent-hook.sh")
    }

    static var readmeURL: URL {
        supportDirectory.appendingPathComponent("README.txt")
    }

    @discardableResult
    static func install(enabledAgents: Set<AgentKind> = Set(AgentKind.allCases)) throws -> URL {
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)

        let script = bundledHookScript()
        try script.write(to: hookScriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: hookScriptURL.path
        )

        if enabledAgents.contains(.claude) {
            try installClaudeHooks()
        }
        try writeGenericConfigs(for: enabledAgents)
        try writeReadme(enabledAgents: enabledAgents)
        return supportDirectory
    }

    static func uninstallClaudeHooks() throws {
        let settingsURL = claudeSettingsURL
        guard FileManager.default.fileExists(atPath: settingsURL.path),
              let data = try? Data(contentsOf: settingsURL),
              var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        guard var hooks = root["hooks"] as? [String: Any] else { return }
        for event in ["PermissionRequest", "SessionStart", "Stop", "Notification", "PostToolUse"] {
            hooks[event] = scrubNotchFlowHooks(from: hooks[event])
            if let entries = hooks[event] as? [Any], entries.isEmpty {
                hooks.removeValue(forKey: event)
            }
        }
        if hooks.isEmpty {
            root.removeValue(forKey: "hooks")
        } else {
            root["hooks"] = hooks
        }
        let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try SecureFileWriter.write(out, to: settingsURL)
    }

    private static var claudeSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
    }

    private static func installClaudeHooks() throws {
        let settingsURL = claudeSettingsURL
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL),
           let existing = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = existing
        }

        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let command = "'\(hookScriptURL.path)'"
        let marker = "notchflow-agent-hook"

        func makeCommandHook(event: String) -> [String: Any] {
            [
                "hooks": [
                    [
                        "type": "command",
                        "command": command,
                    ] as [String: Any],
                ],
            ]
        }

        for event in ["PermissionRequest", "SessionStart", "Stop", "Notification", "PostToolUse"] {
            var entries = (hooks[event] as? [Any]) ?? []
            entries = scrubNotchFlowHooks(from: entries) as? [Any] ?? []
            var entry = makeCommandHook(event: event)
            // Keep a marker for uninstall scrubbing.
            entry["matcher"] = event == "PermissionRequest" ? "" : ""
            // Store command that includes marker path so scrub can find it.
            _ = marker
            entries.append(entry)
            hooks[event] = entries
        }

        root["hooks"] = hooks
        let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try SecureFileWriter.write(out, to: settingsURL)
    }

    private static func scrubNotchFlowHooks(from value: Any?) -> Any? {
        guard let entries = value as? [Any] else { return value }
        let filtered = entries.filter { entry in
            guard let dict = entry as? [String: Any] else { return true }
            let encoded = String(describing: dict)
            return !encoded.contains("notchflow-agent-hook")
        }
        return filtered
    }

    private static func writeGenericConfigs(for agents: Set<AgentKind>) throws {
        let envSnippet = """
        # NotchFlow Agents — source from your shell profile if desired
        export NOTCHFLOW_AGENTS_HOOK="\(hookScriptURL.path)"
        """
        try envSnippet.write(
            to: supportDirectory.appendingPathComponent("env.sh"),
            atomically: true,
            encoding: .utf8
        )

        for agent in agents where agent != .claude {
            let note = """
            NotchFlow Agents — \(agent.displayName)

            Point this agent's notification / hook command at:
              \(hookScriptURL.path)

            The script reads JSON on stdin (Claude Code compatible) or accepts
            NOTCHFLOW_AGENT=\(agent.rawValue) and posts events to the local NotchFlow API.

            See README.txt in this folder for the event schema.
            """
            try note.write(
                to: supportDirectory.appendingPathComponent("\(agent.rawValue).txt"),
                atomically: true,
                encoding: .utf8
            )
        }
    }

    private static func writeReadme(enabledAgents: Set<AgentKind>) throws {
        let list = enabledAgents.map(\.displayName).sorted().joined(separator: ", ")
        let text = """
        NotchFlow Agents
        ================

        Enabled: \(list)

        Hook script:
          \(hookScriptURL.path)

        Claude Code:
          Hooks were merged into ~/.claude/settings.json (PermissionRequest, SessionStart,
          Stop, Notification, PostToolUse). Permission prompts appear in the NotchFlow island
          — Allow / Deny answers the hook.

        Other agents (Codex, Cursor, OpenCode, Gemini CLI, Kimi, DeepSeek):
          See the matching *.txt notes in this folder. Wire their hook/notify command to the
          same script, or POST JSON to NotchFlow Local API:

            POST /v1/agents/events
            Authorization: Bearer <token from Integrations>
            {
              "agent": "codex",
              "event": "permission",
              "sessionId": "…",
              "title": "optimize queries",
              "toolName": "Bash",
              "summary": "npm test",
              "permissionId": "…"
            }

        Poll decision:
            GET /v1/agents/permission/<permissionId>

        Enable Local API in NotchFlow → Settings → Integrations.
        """
        try text.write(to: readmeURL, atomically: true, encoding: .utf8)
    }

    private static func bundledHookScript() -> String {
        let bundles = [ResourceBundle.bundle, Bundle.main]
        for bundle in bundles {
            if let url = bundle.url(forResource: "notchflow-agent-hook", withExtension: "sh", subdirectory: "AgentHooks"),
               let contents = try? String(contentsOf: url, encoding: .utf8) {
                return contents
            }
            if let url = bundle.url(forResource: "notchflow-agent-hook", withExtension: "sh"),
               let contents = try? String(contentsOf: url, encoding: .utf8) {
                return contents
            }
        }
        return embeddedHookScript
    }

    /// Fallback if the resource was not copied into the app bundle.
    private static let embeddedHookScript = #"""
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

PAYLOAD=$(/usr/bin/python3 - <<PY
import json
print(json.dumps({
  "agent": "${AGENT}",
  "event": "${NF_EVENT}",
  "sessionId": "${SESSION_ID}",
  "title": "${TOOL_NAME}" or "${AGENT}",
  "detail": "${SUMMARY}" or "${EVENT_NAME}",
  "toolName": "${TOOL_NAME}",
  "summary": "${SUMMARY}",
  "cwd": "${CWD}",
  "permissionId": "${PERMISSION_ID}",
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

# Wait for Allow/Deny from the notch (up to ~10 minutes).
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

# Timeout — let Claude show its own prompt.
exit 0
"""#
}
