import Foundation

/// How much of an agent's work NotchFlow can follow once its hooks are connected.
enum AgentHookCapability: Equatable, Sendable {
    /// Status in the notch, and permission prompts answered with Allow / Deny in the notch.
    case answersInNotch
    /// Status in the notch only. Prompts pulse the notch but are answered in the agent.
    case statusOnly
}

extension AgentKind {
    /// Agents NotchFlow can wire up from Settings, in the order Settings lists them.
    static let connectableAgents: [AgentKind] = [
        .claude, .codex, .copilot, .qwen, .gemini, .opencode, .kilo, .crush, .droid, .cursor, .grok,
    ]

    /// nil for agents without hooks NotchFlow installs (Kimi, DeepSeek, Grok Bot).
    var hookCapability: AgentHookCapability? {
        switch self {
        case .claude, .codex, .copilot, .qwen:
            .answersInNotch
        case .gemini, .opencode, .kilo, .crush, .droid, .cursor, .grok:
            .statusOnly
        case .kimi, .deepseek, .grokbot:
            nil
        }
    }

    /// Config folders (relative to the home folder) whose presence means the agent was used here.
    var configDirectoryNames: [String] {
        switch self {
        case .claude: [".claude"]
        case .codex: [".codex"]
        case .cursor: [".cursor"]
        case .opencode: [".config/opencode", ".local/share/opencode"]
        case .gemini: [".gemini"]
        case .grok: [".grok"]
        case .copilot: [".copilot"]
        case .qwen: [".qwen"]
        case .kilo: [".config/kilo", ".local/share/kilo"]
        case .crush: [".config/crush", ".local/share/crush"]
        case .droid: [".factory"]
        case .kimi, .deepseek, .grokbot: []
        }
    }

    /// Command names the agent installs on PATH.
    var binaryNames: [String] {
        switch self {
        case .claude: ["claude"]
        case .codex: ["codex"]
        case .cursor: ["cursor-agent", "cursor"]
        case .opencode: ["opencode"]
        case .gemini: ["gemini"]
        case .grok: ["grok"]
        case .copilot: ["copilot"]
        case .qwen: ["qwen"]
        case .kilo: ["kilo", "kilocode"]
        case .crush: ["crush"]
        case .droid: ["droid"]
        case .kimi, .deepseek, .grokbot: []
        }
    }
}

/// Finds which coding agents look installed. Only checks that files exist; never runs anything.
enum AgentDetection {
    /// Standard install locations for CLI binaries, relative to the home folder or absolute.
    static func binaryDirectories(home: URL) -> [URL] {
        [
            home.appendingPathComponent(".local/bin"),
            URL(fileURLWithPath: "/opt/homebrew/bin"),
            URL(fileURLWithPath: "/usr/local/bin"),
            home.appendingPathComponent(".npm-global/bin"),
            home.appendingPathComponent(".bun/bin"),
        ]
    }

    static func isInstalled(
        _ agent: AgentKind,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        binaryDirectories: [URL]? = nil
    ) -> Bool {
        let fileManager = FileManager.default
        for name in agent.configDirectoryNames {
            var isDirectory: ObjCBool = false
            let path = home.appendingPathComponent(name).path
            if fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                return true
            }
        }
        let directories = binaryDirectories ?? Self.binaryDirectories(home: home)
        for directory in directories {
            for binary in agent.binaryNames
            where fileManager.fileExists(atPath: directory.appendingPathComponent(binary).path) {
                return true
            }
        }
        return false
    }

    /// Connectable agents that look installed, in Settings order.
    static func detectedAgents(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        binaryDirectories: [URL]? = nil
    ) -> [AgentKind] {
        AgentKind.connectableAgents.filter {
            isInstalled($0, home: home, binaryDirectories: binaryDirectories)
        }
    }
}
