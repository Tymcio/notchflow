import Foundation

/// Where and how NotchFlow connects each agent. Each agent has a small install / uninstall /
/// status function; all of them take the home folder so tests can use a temporary one.
extension AgentHooksInstaller {
    /// The file NotchFlow writes for `agent` (Droid may use settings.json instead, see below).
    static func configURL(for agent: AgentKind, home: URL) -> URL? {
        let path: String? = switch agent {
        case .claude: ".claude/settings.json"
        case .cursor: ".cursor/hooks.json"
        case .grok: ".grok/hooks/notchflow.json"
        case .codex: ".codex/hooks.json"
        case .copilot: ".copilot/hooks/notchflow.json"
        case .qwen: ".qwen/settings.json"
        case .gemini: ".gemini/settings.json"
        case .opencode: ".config/opencode/plugins/notchflow.js"
        case .kilo: ".config/kilo/plugin/notchflow.js"
        case .crush: ".config/crush/crushrc"
        case .droid: ".factory/hooks.json"
        case .kimi, .deepseek, .grokbot: nil
        }
        return path.map { home.appendingPathComponent($0) }
    }

    static func installHooks(for agent: AgentKind, home: URL, scriptPath: String) throws {
        guard let url = configURL(for: agent, home: home) else { return }
        switch agent {
        case .claude:
            try ExternalConfigFile.updateJSONObject(at: url) { mergeClaudeHooks(into: &$0, scriptPath: scriptPath) }
        case .cursor:
            try ExternalConfigFile.updateJSONObject(at: url) { mergeCursorHooks(into: &$0, scriptPath: scriptPath) }
        case .grok:
            // NotchFlow owns this file, but it still must not clobber something else saved there.
            try ExternalConfigFile.updateJSONObject(at: url) { $0 = grokHooksRoot(scriptPath: scriptPath) }
        case .codex, .qwen, .gemini:
            try ExternalConfigFile.updateJSONObject(at: url) { root in
                mergeNestedHooks(into: &root, agent: agent, scriptPath: scriptPath)
            }
        case .copilot:
            try ExternalConfigFile.updateJSONObject(at: url) { $0 = copilotHooksRoot(scriptPath: scriptPath) }
        case .droid:
            try installDroidHooks(home: home, scriptPath: scriptPath)
        case .opencode, .kilo:
            try installPlugin(at: url, agent: agent, scriptPath: scriptPath)
        case .crush:
            try ExternalConfigFile.updateText(at: url) { crushConfig(replacing: $0, scriptPath: scriptPath) }
        case .kimi, .deepseek, .grokbot:
            break
        }
    }

    static func uninstallHooks(for agent: AgentKind, home: URL) throws {
        guard let url = configURL(for: agent, home: home) else { return }
        switch agent {
        case .claude, .codex, .qwen, .gemini:
            try ExternalConfigFile.updateJSONObject(at: url, createIfMissing: false) {
                scrubHooks(in: &$0, isCursorFormat: false)
            }
        case .cursor:
            try ExternalConfigFile.updateJSONObject(at: url, createIfMissing: false) {
                scrubHooks(in: &$0, isCursorFormat: true)
            }
        case .grok, .copilot:
            try ExternalConfigFile.removeOwnedFile(at: url) { $0.contains(hookMarker) }
        case .droid:
            try uninstallDroidHooks(home: home)
        case .opencode, .kilo:
            try ExternalConfigFile.removeOwnedFile(at: url) { $0.hasPrefix(pluginHeader) }
        case .crush:
            try ExternalConfigFile.updateText(at: url, createIfMissing: false) { text in
                text.map(removingCrushBlock)
            }
        case .kimi, .deepseek, .grokbot:
            break
        }
    }

    static func isConnected(_ agent: AgentKind, home: URL) -> Bool {
        guard let url = configURL(for: agent, home: home) else { return false }
        switch agent {
        case .opencode, .kilo:
            guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else {
                return false
            }
            return text.hasPrefix(pluginHeader)
        case .crush:
            return fileContains(crushBlockStart, at: url)
        case .droid:
            return fileContains(hookMarker, at: url)
                || fileContains(hookMarker, at: droidSettingsURL(home: home))
        default:
            return fileContains(hookMarker, at: url)
        }
    }

    // MARK: - Codex, Qwen Code, Gemini CLI

    /// Hook events per agent, with timeouts in the unit that agent expects.
    static func nestedHookEvents(for agent: AgentKind) -> [(event: String, timeout: Int)] {
        switch agent {
        case .codex:
            // PermissionRequest waits for Allow / Deny in the notch (seconds).
            [("SessionStart", 10), ("UserPromptSubmit", 10), ("PreToolUse", 10),
             ("PostToolUse", 10), ("PermissionRequest", 600), ("Stop", 10)]
        case .qwen:
            [("SessionStart", 10), ("UserPromptSubmit", 10), ("PreToolUse", 10),
             ("PermissionRequest", 600), ("Notification", 10), ("Stop", 10)]
        case .gemini:
            // Gemini CLI timeouts are milliseconds. Monitor only: nothing waits for the notch.
            [("SessionStart", 5000), ("BeforeAgent", 5000), ("BeforeTool", 5000), ("AfterTool", 5000),
             ("Notification", 5000), ("AfterAgent", 5000), ("SessionEnd", 5000)]
        case .droid:
            [("SessionStart", 10), ("UserPromptSubmit", 10), ("PreToolUse", 10),
             ("Notification", 10), ("Stop", 10)]
        default:
            []
        }
    }

    /// Merges NotchFlow's entries into `root["hooks"]`, replacing older NotchFlow entries and
    /// keeping everyone else's.
    static func mergeNestedHooks(into root: inout [String: Any], agent: AgentKind, scriptPath: String) {
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        mergeNestedHookEvents(into: &hooks, agent: agent, scriptPath: scriptPath)
        root["hooks"] = hooks
    }

    static func mergeNestedHookEvents(into hooks: inout [String: Any], agent: AgentKind, scriptPath: String) {
        let name: String? = agent == .gemini ? "notchflow" : nil
        for (event, timeout) in nestedHookEvents(for: agent) {
            var entries = scrubNotchFlowHooks(from: hooks[event] as? [Any] ?? []) as? [Any] ?? []
            let command = envCommand(agent: agent, event: event, scriptPath: scriptPath)
            entries.append(nestedHookGroup(command: command, timeout: timeout, name: name))
            hooks[event] = entries
        }
    }

    // MARK: - Copilot CLI

    /// `~/.copilot/hooks/notchflow.json`. Copilot denies a tool when a preToolUse command fails,
    /// so the command ends with `|| true` (the script itself also always exits 0).
    static func copilotHooksRoot(scriptPath: String) -> [String: Any] {
        let events: [(String, Int)] = [
            ("sessionStart", 10), ("userPromptSubmitted", 10), ("preToolUse", 10),
            ("permissionRequest", 600), ("notification", 10), ("agentStop", 10), ("sessionEnd", 10),
        ]
        var hooks: [String: Any] = [:]
        for (event, timeout) in events {
            hooks[event] = [[
                "type": "command",
                "bash": "\(shellQuote(scriptPath)) || true",
                "env": ["NOTCHFLOW_AGENT": AgentKind.copilot.rawValue, "NOTCHFLOW_HOOK_EVENT": event],
                "timeoutSec": timeout,
            ] as [String: Any]]
        }
        return ["version": 1, "hooks": hooks]
    }

    // MARK: - Droid

    static func droidSettingsURL(home: URL) -> URL {
        home.appendingPathComponent(".factory/settings.json")
    }

    /// Droid reads `~/.factory/hooks.json` (events at the top level). Only when that file is
    /// missing does it read a `hooks` key in settings.json; if the user keeps hooks there,
    /// NotchFlow adds to them instead of creating hooks.json (which would hide them).
    private static func installDroidHooks(home: URL, scriptPath: String) throws {
        let hooksURL = home.appendingPathComponent(".factory/hooks.json")
        let settingsURL = droidSettingsURL(home: home)
        let hooksFileExists = FileManager.default.fileExists(atPath: hooksURL.path)
        if !hooksFileExists, settingsHaveHooks(at: settingsURL) {
            try ExternalConfigFile.updateJSONObject(at: settingsURL, createIfMissing: false) { root in
                mergeNestedHooks(into: &root, agent: .droid, scriptPath: scriptPath)
            }
            return
        }
        try ExternalConfigFile.updateJSONObject(at: hooksURL) { root in
            mergeNestedHookEvents(into: &root, agent: .droid, scriptPath: scriptPath)
        }
    }

    private static func uninstallDroidHooks(home: URL) throws {
        try ExternalConfigFile.updateJSONObject(
            at: home.appendingPathComponent(".factory/hooks.json"),
            createIfMissing: false
        ) { root in
            root = scrubHookMap(root)
        }
        if fileContains(hookMarker, at: droidSettingsURL(home: home)) {
            try ExternalConfigFile.updateJSONObject(at: droidSettingsURL(home: home), createIfMissing: false) {
                scrubHooks(in: &$0, isCursorFormat: false)
            }
        }
    }

    private static func settingsHaveHooks(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return root["hooks"] != nil
    }
}
