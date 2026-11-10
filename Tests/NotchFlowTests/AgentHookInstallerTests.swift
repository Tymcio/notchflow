import XCTest
@testable import NotchFlow

/// Every installer runs against a temporary home folder; real agent configs are never touched.
final class AgentHookInstallerTests: XCTestCase {
    private var home: URL!
    private let script = "/Users/test/Library/Application Support/NotchFlow/Agents/notchflow-agent-hook.sh"

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("nf-agents-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    // MARK: - Helpers

    private func url(_ path: String) -> URL { home.appendingPathComponent(path) }

    private func write(_ text: String, to path: String) throws {
        let file = url(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    private func read(_ path: String) throws -> String {
        try String(contentsOf: url(path), encoding: .utf8)
    }

    private func json(_ path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: url(path))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func install(_ agent: AgentKind) throws {
        try AgentHooksInstaller.installHooks(for: agent, home: home, scriptPath: script)
    }

    /// Installs twice and checks the second run changes nothing.
    private func installTwice(_ agent: AgentKind, file: String) throws {
        try install(agent)
        let first = try Data(contentsOf: url(file))
        try install(agent)
        XCTAssertEqual(try Data(contentsOf: url(file)), first, "\(agent) install is not idempotent")
        XCTAssertTrue(AgentHooksInstaller.isConnected(agent, home: home))
    }

    private func commands(in groups: Any?) -> [String] {
        (groups as? [[String: Any]] ?? []).flatMap { group in
            (group["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
        }
    }

    // MARK: - Codex

    func testCodexMergesHooksAndKeepsTheUsersOwnHook() throws {
        try write("""
        {"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"~/bin/mine.sh"}]}]},"description":"mine"}
        """, to: ".codex/hooks.json")
        try write("model = \"gpt-5\"\n", to: ".codex/config.toml")

        try installTwice(.codex, file: ".codex/hooks.json")

        let root = try json(".codex/hooks.json")
        XCTAssertEqual(root["description"] as? String, "mine")
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        let sessionStart = commands(in: hooks["SessionStart"])
        XCTAssertEqual(sessionStart.count, 2)
        XCTAssertEqual(sessionStart.first, "~/bin/mine.sh")
        XCTAssertTrue(sessionStart[1].contains("NOTCHFLOW_AGENT=codex"))
        XCTAssertTrue(sessionStart[1].hasSuffix("'\(script)'"))
        for event in ["UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop"] {
            XCTAssertEqual(commands(in: hooks[event]).count, 1, event)
        }
        let permission = try XCTUnwrap((hooks["PermissionRequest"] as? [[String: Any]])?.first)
        let handler = try XCTUnwrap((permission["hooks"] as? [[String: Any]])?.first)
        XCTAssertEqual(handler["timeout"] as? Int, 600)
        XCTAssertNil(permission["matcher"], "\"*\" is not a valid Codex matcher regex")
        XCTAssertEqual(try read(".codex/config.toml"), "model = \"gpt-5\"\n", "trust hashes live here; never touch it")

        try AgentHooksInstaller.uninstallHooks(for: .codex, home: home)
        let after = try json(".codex/hooks.json")
        let afterHooks = try XCTUnwrap(after["hooks"] as? [String: Any])
        XCTAssertEqual(Array(afterHooks.keys), ["SessionStart"])
        XCTAssertEqual(commands(in: afterHooks["SessionStart"]), ["~/bin/mine.sh"])
        XCTAssertFalse(AgentHooksInstaller.isConnected(.codex, home: home))
    }

    // MARK: - Qwen Code and Gemini CLI

    func testQwenMergesIntoSettingsAndKeepsOtherKeys() throws {
        try write(#"{"model":{"name":"qwen3-coder"},"hooks":{"Stop":[{"hooks":[{"type":"command","command":"say hi"}]}]}}"#,
                  to: ".qwen/settings.json")
        try installTwice(.qwen, file: ".qwen/settings.json")

        let root = try json(".qwen/settings.json")
        XCTAssertNotNil(root["model"])
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        XCTAssertEqual(commands(in: hooks["Stop"]).count, 2)
        XCTAssertTrue(commands(in: hooks["PermissionRequest"]).first?.contains("NOTCHFLOW_AGENT=qwen") == true)
        XCTAssertNotNil(hooks["Notification"])

        try AgentHooksInstaller.uninstallHooks(for: .qwen, home: home)
        let after = try json(".qwen/settings.json")
        XCTAssertNotNil(after["model"])
        XCTAssertEqual(commands(in: (after["hooks"] as? [String: Any])?["Stop"]), ["say hi"])
    }

    func testGeminiUsesMillisecondTimeoutsAndNeverWaitsForPermission() throws {
        try write(#"{"theme":"Dracula","security":{"auth":{"selectedType":"oauth-personal"}}}"#, to: ".gemini/settings.json")
        try installTwice(.gemini, file: ".gemini/settings.json")

        let root = try json(".gemini/settings.json")
        XCTAssertEqual(root["theme"] as? String, "Dracula")
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        XCTAssertEqual(
            Set(hooks.keys),
            ["SessionStart", "BeforeAgent", "BeforeTool", "AfterTool", "Notification", "AfterAgent", "SessionEnd"]
        )
        let group = try XCTUnwrap((hooks["BeforeTool"] as? [[String: Any]])?.first)
        let handler = try XCTUnwrap((group["hooks"] as? [[String: Any]])?.first)
        XCTAssertEqual(handler["timeout"] as? Int, 5000)
        XCTAssertEqual(handler["name"] as? String, "notchflow")

        try AgentHooksInstaller.uninstallHooks(for: .gemini, home: home)
        let after = try json(".gemini/settings.json")
        XCTAssertNil(after["hooks"])
        XCTAssertEqual(after["theme"] as? String, "Dracula")
        XCTAssertNotNil(after["security"])
    }

    // MARK: - Copilot CLI

    func testCopilotWritesItsOwnFileThatNeverFailsClosed() throws {
        try write(#"{"version":1,"hooks":{"preToolUse":[{"type":"command","bash":"./mine.sh"}]}}"#,
                  to: ".copilot/hooks/mine.json")
        try installTwice(.copilot, file: ".copilot/hooks/notchflow.json")

        let root = try json(".copilot/hooks/notchflow.json")
        XCTAssertEqual(root["version"] as? Int, 1)
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        for event in ["sessionStart", "preToolUse", "permissionRequest", "notification", "agentStop"] {
            let entry = try XCTUnwrap((hooks[event] as? [[String: Any]])?.first, event)
            XCTAssertEqual(entry["type"] as? String, "command")
            XCTAssertEqual(entry["bash"] as? String, "'\(script)' || true")
            let env = try XCTUnwrap(entry["env"] as? [String: String])
            XCTAssertEqual(env, ["NOTCHFLOW_AGENT": "copilot", "NOTCHFLOW_HOOK_EVENT": event])
        }
        let permission = try XCTUnwrap((hooks["permissionRequest"] as? [[String: Any]])?.first)
        XCTAssertEqual(permission["timeoutSec"] as? Int, 600)

        try AgentHooksInstaller.uninstallHooks(for: .copilot, home: home)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url(".copilot/hooks/notchflow.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url(".copilot/hooks/mine.json").path))
    }

    func testCopilotUninstallLeavesAFileNotchFlowDidNotWrite() throws {
        try write(#"{"version":1,"hooks":{}}"#, to: ".copilot/hooks/notchflow.json")
        try AgentHooksInstaller.uninstallHooks(for: .copilot, home: home)
        XCTAssertEqual(try read(".copilot/hooks/notchflow.json"), #"{"version":1,"hooks":{}}"#)
    }

    // MARK: - Droid

    func testDroidWritesTopLevelEventsInHooksJSON() throws {
        try write(#"{"PreToolUse":[{"matcher":"Execute","hooks":[{"type":"command","command":"/usr/local/bin/audit.sh"}]}]}"#,
                  to: ".factory/hooks.json")
        try installTwice(.droid, file: ".factory/hooks.json")

        let root = try json(".factory/hooks.json")
        XCTAssertNil(root["hooks"], "hooks.json has no wrapper")
        XCTAssertEqual(commands(in: root["PreToolUse"]).count, 2)
        XCTAssertEqual(Set(root.keys), ["SessionStart", "UserPromptSubmit", "PreToolUse", "Notification", "Stop"])

        try AgentHooksInstaller.uninstallHooks(for: .droid, home: home)
        let after = try json(".factory/hooks.json")
        XCTAssertEqual(Array(after.keys), ["PreToolUse"])
        XCTAssertEqual(commands(in: after["PreToolUse"]), ["/usr/local/bin/audit.sh"])
    }

    func testDroidAddsToSettingsHooksWhenTheUserKeepsThemThere() throws {
        try write(#"{"model":"x","hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}"#,
                  to: ".factory/settings.json")
        try installTwice(.droid, file: ".factory/settings.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url(".factory/hooks.json").path),
                       "creating hooks.json would hide the user's settings.json hooks")
        let hooks = try XCTUnwrap(try json(".factory/settings.json")["hooks"] as? [String: Any])
        XCTAssertEqual(commands(in: hooks["Stop"]).count, 2)

        try AgentHooksInstaller.uninstallHooks(for: .droid, home: home)
        let after = try json(".factory/settings.json")
        XCTAssertEqual(after["model"] as? String, "x")
        XCTAssertEqual(commands(in: (after["hooks"] as? [String: Any])?["Stop"]), ["say done"])
        XCTAssertFalse(AgentHooksInstaller.isConnected(.droid, home: home))
    }

    // MARK: - OpenCode and Kilo Code

    func testPluginsAreWrittenOnlyOverNotchFlowsOwnFile() throws {
        try write("export const Mine = async () => ({})\n", to: ".config/opencode/plugins/other.js")
        try installTwice(.opencode, file: ".config/opencode/plugins/notchflow.js")
        try installTwice(.kilo, file: ".config/kilo/plugin/notchflow.js")

        let source = try read(".config/opencode/plugins/notchflow.js")
        XCTAssertTrue(source.hasPrefix("// Installed by NotchFlow"))
        XCTAssertTrue(source.contains(#"const HOOK = "\#(script)""#))
        XCTAssertTrue(source.contains(#"const AGENT = "opencode""#))
        XCTAssertTrue(source.contains("export default { id: \"notchflow\", setup, server }"))
        XCTAssertTrue(try read(".config/kilo/plugin/notchflow.js").contains(#"const AGENT = "kilo""#))

        try AgentHooksInstaller.uninstallHooks(for: .opencode, home: home)
        try AgentHooksInstaller.uninstallHooks(for: .kilo, home: home)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url(".config/opencode/plugins/notchflow.js").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url(".config/kilo/plugin/notchflow.js").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url(".config/opencode/plugins/other.js").path))
    }

    func testPluginRefusesToReplaceSomeoneElsesFile() throws {
        try write("// my own notchflow plugin\n", to: ".config/opencode/plugins/notchflow.js")
        XCTAssertThrowsError(try install(.opencode)) { error in
            XCTAssertEqual(
                error as? ExternalConfigError,
                .notOwnedByNotchFlow(path: url(".config/opencode/plugins/notchflow.js").path)
            )
        }
        try AgentHooksInstaller.uninstallHooks(for: .opencode, home: home)
        XCTAssertEqual(try read(".config/opencode/plugins/notchflow.js"), "// my own notchflow plugin\n")
        XCTAssertFalse(AgentHooksInstaller.isConnected(.opencode, home: home))
    }

    // MARK: - Crush

    func testCrushAppendsAManagedBlockAndRemovesOnlyThatBlock() throws {
        let original = "provider add ollama --type ollama\nhook add TurnEnd --command 'afplay /System/Library/Sounds/Glass.aiff'\n"
        try write(original, to: ".config/crush/crushrc")
        try installTwice(.crush, file: ".config/crush/crushrc")

        let text = try read(".config/crush/crushrc")
        XCTAssertTrue(text.hasPrefix(original))
        XCTAssertEqual(text.components(separatedBy: AgentHooksInstaller.crushBlockStart).count, 2)
        XCTAssertTrue(text.contains(
            "hook add PreToolUse --name notchflow --timeout 10 --command "
                + "'env NOTCHFLOW_AGENT=crush NOTCHFLOW_HOOK_EVENT=PreToolUse '\\''\(script)'\\'''"
        ))
        for event in ["SessionStart", "TurnStart", "PermissionRequest", "TurnEnd"] {
            XCTAssertTrue(text.contains("hook add \(event) --name notchflow"), event)
        }

        try AgentHooksInstaller.uninstallHooks(for: .crush, home: home)
        XCTAssertEqual(try read(".config/crush/crushrc"), original)
        XCTAssertFalse(AgentHooksInstaller.isConnected(.crush, home: home))
    }

    func testCrushCreatesTheFileWhenMissingAndKeepsLinesAddedAfterTheBlock() throws {
        try install(.crush)
        var text = try read(".config/crush/crushrc")
        XCTAssertTrue(text.hasPrefix(AgentHooksInstaller.crushBlockStart))
        text += "option progress false\n"
        try write(text, to: ".config/crush/crushrc")

        try AgentHooksInstaller.uninstallHooks(for: .crush, home: home)
        XCTAssertEqual(try read(".config/crush/crushrc"), "option progress false\n")
    }

    // MARK: - Claude Code, Cursor and Grok Build

    func testClaudeCursorAndGrokRoundTrip() throws {
        try write(#"{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}"#,
                  to: ".claude/settings.json")
        try write(#"{"version":1,"hooks":{"stop":[{"command":"./mine.sh"}]}}"#, to: ".cursor/hooks.json")
        try installTwice(.claude, file: ".claude/settings.json")
        try installTwice(.cursor, file: ".cursor/hooks.json")
        try installTwice(.grok, file: ".grok/hooks/notchflow.json")

        XCTAssertEqual(commands(in: (try json(".claude/settings.json")["hooks"] as? [String: Any])?["Stop"]).last,
                       "'\(script)'")

        for agent: AgentKind in [.claude, .cursor, .grok] {
            try AgentHooksInstaller.uninstallHooks(for: agent, home: home)
            XCTAssertFalse(AgentHooksInstaller.isConnected(agent, home: home), "\(agent)")
        }
        XCTAssertEqual(commands(in: (try json(".claude/settings.json")["hooks"] as? [String: Any])?["Stop"]), ["say done"])
        XCTAssertEqual(try json(".claude/settings.json")["model"] as? String, "opus")
        let cursorStop = (try json(".cursor/hooks.json")["hooks"] as? [String: Any])?["stop"] as? [[String: Any]]
        XCTAssertEqual(cursorStop?.compactMap { $0["command"] as? String }, ["./mine.sh"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: url(".grok/hooks/notchflow.json").path))
    }

    // MARK: - End to end

    func testInstallConnectsSelectedAgentsAndUninstallRemovesThemAll() throws {
        let selected: Set<AgentKind> = [.codex, .copilot, .crush, .opencode]
        let folder = try AgentHooksInstaller.install(enabledAgents: selected, home: home)
        let scriptURL = AgentHooksInstaller.hookScriptURL(home: home)

        XCTAssertEqual(folder, AgentHooksInstaller.supportDirectory(home: home))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: scriptURL.path))
        let stop = commands(in: (try json(".codex/hooks.json")["hooks"] as? [String: Any])?["Stop"])
        XCTAssertEqual(stop, ["env NOTCHFLOW_AGENT=codex NOTCHFLOW_HOOK_EVENT=Stop '\(scriptURL.path)'"])
        XCTAssertTrue(try read("Library/Application Support/NotchFlow/Agents/README.txt").contains("/hooks"))

        let status = AgentHooksInstaller.currentStatus(localAPIEnabled: true, home: home)
        XCTAssertEqual(status.connectedAgents, selected)
        XCTAssertTrue(status.isReady)

        try AgentHooksInstaller.uninstall(home: home)
        XCTAssertTrue(AgentHooksInstaller.currentStatus(localAPIEnabled: true, home: home).connectedAgents.isEmpty)
    }

    func testNonJSONConfigIsLeftAlone() throws {
        try write("// comments are not JSON\n{\"theme\":\"x\"}\n", to: ".gemini/settings.json")
        XCTAssertThrowsError(try install(.gemini))
        XCTAssertEqual(try read(".gemini/settings.json"), "// comments are not JSON\n{\"theme\":\"x\"}\n")
    }
}
