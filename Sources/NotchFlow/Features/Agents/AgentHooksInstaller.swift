import Foundation

/// Installs local hook scripts and wires Claude Code + Cursor configs.
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

    struct SetupStatus: Equatable, Sendable {
        var localAPIEnabled: Bool
        var hookScriptInstalled: Bool
        var claudeHooksInstalled: Bool
        var cursorHooksInstalled: Bool

        var isReady: Bool {
            localAPIEnabled && hookScriptInstalled && (claudeHooksInstalled || cursorHooksInstalled)
        }
    }

    static func currentStatus(localAPIEnabled: Bool) -> SetupStatus {
        SetupStatus(
            localAPIEnabled: localAPIEnabled,
            hookScriptInstalled: FileManager.default.isExecutableFile(atPath: hookScriptURL.path)
                || FileManager.default.fileExists(atPath: hookScriptURL.path),
            claudeHooksInstalled: fileContainsNotchFlowHook(at: claudeSettingsURL),
            cursorHooksInstalled: fileContainsNotchFlowHook(at: cursorHooksURL)
        )
    }

    @discardableResult
    static func install(enabledAgents: Set<AgentKind> = Set(AgentKind.allCases)) throws -> URL {
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        try refreshBundledScript()

        if enabledAgents.contains(.claude) {
            try installClaudeHooks()
        }
        if enabledAgents.contains(.cursor) {
            try installCursorHooks()
        }
        try writeGenericConfigs(for: enabledAgents)
        try writeReadme(enabledAgents: enabledAgents)
        return supportDirectory
    }

    /// Updates the shared hook script without rewriting Claude/Cursor configs.
    static func refreshBundledScript() throws {
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        let script = bundledHookScript()
        try script.write(to: hookScriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: hookScriptURL.path
        )
    }

    static func uninstallClaudeHooks() throws {
        try scrubHooksFile(at: claudeSettingsURL, isCursorFormat: false)
    }

    static func uninstallCursorHooks() throws {
        try scrubHooksFile(at: cursorHooksURL, isCursorFormat: true)
    }

    // MARK: - Paths

    private static var claudeSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
    }

    private static var cursorHooksURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor/hooks.json")
    }

    // MARK: - Claude

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
        let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try SecureFileWriter.write(out, to: settingsURL)
    }

    // MARK: - Cursor

    private static func installCursorHooks() throws {
        let hooksURL = cursorHooksURL
        try FileManager.default.createDirectory(
            at: hooksURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var root: [String: Any] = ["version": 1]
        if let data = try? Data(contentsOf: hooksURL),
           let existing = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = existing
            if root["version"] == nil {
                root["version"] = 1
            }
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
            let command =
                "env NOTCHFLOW_AGENT=cursor NOTCHFLOW_HOOK_EVENT=\(event) '\(hookScriptURL.path)'"
            entries.append([
                "command": command,
            ] as [String: Any])
            hooks[event] = entries
        }

        root["hooks"] = hooks
        let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try SecureFileWriter.write(out, to: hooksURL)
    }

    // MARK: - Shared

    private static func scrubHooksFile(at url: URL, isCursorFormat: Bool) throws {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        guard var hooks = root["hooks"] as? [String: Any] else { return }
        for key in Array(hooks.keys) {
            hooks[key] = scrubNotchFlowHooks(from: hooks[key])
            if let entries = hooks[key] as? [Any], entries.isEmpty {
                hooks.removeValue(forKey: key)
            }
        }
        if hooks.isEmpty {
            root.removeValue(forKey: "hooks")
        } else {
            root["hooks"] = hooks
        }
        if isCursorFormat, root["version"] == nil {
            root["version"] = 1
        }
        let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try SecureFileWriter.write(out, to: url)
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

    private static func fileContainsNotchFlowHook(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return false
        }
        return text.contains("notchflow-agent-hook")
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

        let cursorNote = """
        NotchFlow Agents — Cursor

        Po „Połącz agentów” NotchFlow dopisuje hooki monitorujące do:
          ~/.cursor/hooks.json

        Restart Cursor (Cmd+Q → otwórz ponownie), potem Agent Chat.
        Status sesji pojawia się w notchu. Cursor nadal pokazuje własne pytania o zgodę
        (NotchFlow nie blokuje beforeShellExecution / preToolUse).

        Claude Code: Allow / Deny w notchu działa przez PermissionRequest hooks.

        Docs: https://cursor.com/docs/hooks
        """
        try cursorNote.write(
            to: supportDirectory.appendingPathComponent("cursor.txt"),
            atomically: true,
            encoding: .utf8
        )

        for agent in agents where agent != .claude && agent != .cursor {
            let note = """
            NotchFlow Agents — \(agent.displayName)

            Point this agent's notification / hook command at:
              \(hookScriptURL.path)

            Example:
              env NOTCHFLOW_AGENT=\(agent.rawValue) '\(hookScriptURL.path)'

            Or POST JSON to NotchFlow Local API /v1/agents/events (see README.txt).
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
          Hooks merged into ~/.claude/settings.json
          Permission prompts can be answered from the NotchFlow island.

        Cursor:
          Hooks merged into ~/.cursor/hooks.json (monitor only — session/tool status).
          Restart Cursor after install. Cursor keeps its own permission prompts.
          NotchFlow does not block beforeShellExecution / preToolUse.

        Other agents:
          See *.txt notes in this folder, or POST /v1/agents/events

        Local API must stay enabled (Settings → Integrations).
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
        // Minimal fallback — prefer reinstall from a current app build.
        return """
        #!/bin/bash
        echo "NotchFlow agent hook missing from app bundle — reinstall / update NotchFlow" >&2
        exit 0
        """
    }
}
