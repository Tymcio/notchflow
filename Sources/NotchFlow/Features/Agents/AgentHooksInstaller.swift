import Foundation

/// Installs the local hook script and wires it into each coding agent's own config.
///
/// Other tools' config files go through `ExternalConfigFile`: symlinks are followed,
/// permissions kept, a one-time `.notchflow-backup` is saved, and a file that is not a
/// JSON object (or text, for Crush) is left alone with an error instead of being replaced.
/// Every path takes a home folder so tests can run against a temporary one.
enum AgentHooksInstaller {
    /// Every hook entry NotchFlow writes runs this script, so its name marks NotchFlow's entries.
    static let hookMarker = "notchflow-agent-hook"

    static var defaultHome: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    static func supportDirectory(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/NotchFlow/Agents", isDirectory: true)
    }

    private static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchFlow/Agents", isDirectory: true)
    }

    static var hookScriptURL: URL {
        supportDirectory.appendingPathComponent("notchflow-agent-hook.sh")
    }

    static func hookScriptURL(home: URL) -> URL {
        supportDirectory(home: home).appendingPathComponent("notchflow-agent-hook.sh")
    }

    static var readmeURL: URL {
        supportDirectory.appendingPathComponent("README.txt")
    }

    struct SetupStatus: Equatable, Sendable {
        var localAPIEnabled: Bool
        var hookScriptInstalled: Bool
        var connectedAgents: Set<AgentKind>

        var claudeHooksInstalled: Bool { connectedAgents.contains(.claude) }
        var cursorHooksInstalled: Bool { connectedAgents.contains(.cursor) }
        var grokHooksInstalled: Bool { connectedAgents.contains(.grok) }

        var isReady: Bool {
            localAPIEnabled && hookScriptInstalled && !connectedAgents.isEmpty
        }
    }

    static func currentStatus(localAPIEnabled: Bool, home: URL? = nil) -> SetupStatus {
        let script = home.map(hookScriptURL(home:)) ?? hookScriptURL
        let home = home ?? defaultHome
        return SetupStatus(
            localAPIEnabled: localAPIEnabled,
            hookScriptInstalled: FileManager.default.fileExists(atPath: script.path),
            connectedAgents: Set(AgentKind.connectableAgents.filter { isConnected($0, home: home) })
        )
    }

    /// Writes the hook script and connects each enabled agent. Returns the hooks folder.
    @discardableResult
    static func install(
        enabledAgents: Set<AgentKind> = Set(AgentKind.connectableAgents),
        home: URL? = nil
    ) throws -> URL {
        let directory = home.map(supportDirectory(home:)) ?? supportDirectory
        let script = home.map(hookScriptURL(home:)) ?? hookScriptURL
        let home = home ?? defaultHome
        try writeBundledScript(to: script)

        for agent in AgentKind.connectableAgents where enabledAgents.contains(agent) {
            try installHooks(for: agent, home: home, scriptPath: script.path)
        }
        try writeReadme(in: directory, scriptPath: script.path, enabledAgents: enabledAgents)
        return directory
    }

    /// Removes NotchFlow's entries and files from each agent. Everything else stays.
    static func uninstall(
        agents: Set<AgentKind> = Set(AgentKind.connectableAgents),
        home: URL? = nil
    ) throws {
        let home = home ?? defaultHome
        var firstError: Error?
        for agent in AgentKind.connectableAgents where agents.contains(agent) {
            do {
                try uninstallHooks(for: agent, home: home)
            } catch {
                firstError = firstError ?? error
            }
        }
        if let firstError { throw firstError }
    }

    /// Updates the shared hook script without rewriting any agent's config.
    static func refreshBundledScript() throws {
        try writeBundledScript(to: hookScriptURL)
    }

    private static func writeBundledScript(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try bundledHookScript().write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    static func uninstallClaudeHooks(home: URL? = nil) throws {
        try uninstallHooks(for: .claude, home: home ?? defaultHome)
    }

    static func uninstallCursorHooks(home: URL? = nil) throws {
        try uninstallHooks(for: .cursor, home: home ?? defaultHome)
    }

    // MARK: - Commands

    /// Single-quotes `value` for a POSIX shell.
    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// `env NOTCHFLOW_AGENT=<agent> NOTCHFLOW_HOOK_EVENT=<event> '<script>'`
    static func envCommand(agent: AgentKind, event: String, scriptPath: String) -> String {
        "env NOTCHFLOW_AGENT=\(agent.rawValue) NOTCHFLOW_HOOK_EVENT=\(event) \(shellQuote(scriptPath))"
    }

    // MARK: - Claude

    static func mergeClaudeHooks(into root: inout [String: Any], scriptPath: String) {
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let command = shellQuote(scriptPath)

        for event in ["PermissionRequest", "SessionStart", "Stop", "Notification", "PostToolUse"] {
            var entries = (hooks[event] as? [Any]) ?? []
            entries = scrubNotchFlowHooks(from: entries) as? [Any] ?? []
            entries.append([
                "hooks": [
                    [
                        "type": "command",
                        "command": command,
                    ] as [String: Any],
                ],
            ] as [String: Any])
            hooks[event] = entries
        }

        root["hooks"] = hooks
    }

    // MARK: - Cursor

    static func mergeCursorHooks(into root: inout [String: Any], scriptPath: String) {
        if root["version"] == nil {
            root["version"] = 1
        }

        var hooks = root["hooks"] as? [String: Any] ?? [:]
        // Cursor: observe + jump-on-attention. beforeShell/MCP never wait for NotchFlow
        // Allow/Deny (Cursor keeps its own Skip/Run UI — same model as Vibe Island).
        let events = [
            "sessionStart",
            "sessionEnd",
            "stop",
            "beforeShellExecution",
            "beforeMCPExecution",
            "afterShellExecution",
            "postToolUse",
            "afterFileEdit",
        ]
        // Scrub old preToolUse blockers that used to hang Cursor.
        for stale in ["preToolUse"] {
            if let scrubbed = scrubNotchFlowHooks(from: hooks[stale]) as? [Any], scrubbed.isEmpty {
                hooks.removeValue(forKey: stale)
            } else if let scrubbed = scrubNotchFlowHooks(from: hooks[stale]) {
                hooks[stale] = scrubbed
            }
        }

        for event in events {
            var entries = (hooks[event] as? [Any]) ?? []
            entries = scrubNotchFlowHooks(from: entries) as? [Any] ?? []
            entries.append([
                "command": envCommand(agent: .cursor, event: event, scriptPath: scriptPath),
            ] as [String: Any])
            hooks[event] = entries
        }

        root["hooks"] = hooks
    }

    // MARK: - Grok Build

    /// Monitor-only. Grok Build keeps its own permission prompts; PreToolUse is not installed.
    static func grokHooksRoot(scriptPath: String) -> [String: Any] {
        var hooks: [String: Any] = [:]
        let events = ["SessionStart", "PostToolUse", "Stop", "SessionEnd", "StopFailure", "Notification"]
        for event in events {
            hooks[event] = [nestedHookGroup(
                command: envCommand(agent: .grok, event: event, scriptPath: scriptPath),
                timeout: 10
            )]
        }
        return ["hooks": hooks]
    }

    // MARK: - Shared

    /// `{"hooks": [{"type": "command", "command": …, "timeout": …}]}`, the matcher-group shape
    /// shared by Claude Code, Codex, Qwen Code, Gemini CLI, Droid and Grok Build.
    static func nestedHookGroup(command: String, timeout: Int, name: String? = nil) -> [String: Any] {
        var hook: [String: Any] = ["type": "command", "command": command, "timeout": timeout]
        if let name { hook["name"] = name }
        return ["hooks": [hook]]
    }

    static func scrubHooks(in root: inout [String: Any], isCursorFormat: Bool) {
        guard let hooks = root["hooks"] as? [String: Any] else { return }
        let scrubbed = scrubHookMap(hooks)
        if scrubbed.isEmpty {
            root.removeValue(forKey: "hooks")
        } else {
            root["hooks"] = scrubbed
        }
        if isCursorFormat, root["version"] == nil {
            root["version"] = 1
        }
    }

    /// Drops NotchFlow's entries from an `{event: [entries]}` map, and events left empty.
    static func scrubHookMap(_ hooks: [String: Any]) -> [String: Any] {
        var hooks = hooks
        for key in Array(hooks.keys) {
            guard hooks[key] is [Any] else { continue }
            hooks[key] = scrubNotchFlowHooks(from: hooks[key])
            if let entries = hooks[key] as? [Any], entries.isEmpty {
                hooks.removeValue(forKey: key)
            }
        }
        return hooks
    }

    static func scrubNotchFlowHooks(from value: Any?) -> Any? {
        guard let entries = value as? [Any] else { return value }
        let filtered = entries.filter { entry in
            guard let dict = entry as? [String: Any] else { return true }
            let encoded = String(describing: dict)
            return !encoded.contains(hookMarker)
        }
        return filtered
    }

    static func fileContains(_ marker: String, at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return false
        }
        return text.contains(marker)
    }

    private static func writeReadme(in directory: URL, scriptPath: String, enabledAgents: Set<AgentKind>) throws {
        let list = AgentKind.connectableAgents
            .filter { enabledAgents.contains($0) }
            .map(\.displayName)
            .joined(separator: ", ")
        let text = """
        NotchFlow Agents
        ================

        Connected: \(list)

        Hook script:
          \(scriptPath)

        Allow / Deny in the notch: Claude Code, Codex, Copilot CLI, Qwen Code.
        Status only (answer prompts in the agent): Gemini CLI, OpenCode, Kilo Code, Crush, Droid,
        Cursor, Grok Build.

        Codex: run /hooks in Codex once and trust the NotchFlow hook. Codex skips new hooks until then.
        Restart running agents after connecting so they load the hooks.

        Config NotchFlow writes (Disconnect in Settings removes only NotchFlow's entries):
          Claude Code  ~/.claude/settings.json
          Codex        ~/.codex/hooks.json
          Copilot CLI  ~/.copilot/hooks/notchflow.json
          Qwen Code    ~/.qwen/settings.json
          Gemini CLI   ~/.gemini/settings.json
          OpenCode     ~/.config/opencode/plugins/notchflow.js
          Kilo Code    ~/.config/kilo/plugin/notchflow.js
          Crush        ~/.config/crush/crushrc (block between NotchFlow markers)
          Droid        ~/.factory/hooks.json
          Cursor       ~/.cursor/hooks.json
          Grok Build   ~/.grok/hooks/notchflow.json

        Other agents: run the hook script with NOTCHFLOW_AGENT=<name>, or POST /v1/agents/events.
        Local API must stay enabled (Settings → Integrations).
        """
        try text.write(to: directory.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
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
        // Minimal fallback — prefer reinstall from a current app build.
        return """
        #!/bin/bash
        echo "NotchFlow agent hook missing from app bundle — reinstall / update NotchFlow" >&2
        exit 0
        """
    }
}
