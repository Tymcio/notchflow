import Foundation

/// Closed set of AI coding agents supported by the NotchFlow Agents addon.
enum AgentKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case claude
    case codex
    case cursor
    case opencode
    case gemini
    case kimi
    case deepseek

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .opencode: "OpenCode"
        case .gemini: "Gemini CLI"
        case .kimi: "Kimi Code"
        case .deepseek: "DeepSeek"
        }
    }

    var systemImage: String {
        switch self {
        case .claude: "brain.head.profile"
        case .codex: "terminal"
        case .cursor: "curlybraces"
        case .opencode: "chevron.left.forwardslash.chevron.right"
        case .gemini: "sparkle"
        case .kimi: "moon.stars"
        case .deepseek: "waveform"
        }
    }

    /// Bundle IDs used when jumping back to the agent / terminal host.
    var preferredBundleIDs: [String] {
        switch self {
        case .claude:
            ["com.googlecode.iterm2", "com.apple.Terminal", "com.github.wez.wezterm", "com.mitchellh.ghostty"]
        case .codex:
            ["com.googlecode.iterm2", "com.apple.Terminal", "com.mitchellh.ghostty"]
        case .cursor:
            ["com.todesktop.230313mzl4w4u92", "com.cursorapp.Cursor"]
        case .opencode:
            ["com.googlecode.iterm2", "com.apple.Terminal", "com.mitchellh.ghostty"]
        case .gemini:
            ["com.googlecode.iterm2", "com.apple.Terminal"]
        case .kimi:
            ["com.googlecode.iterm2", "com.apple.Terminal"]
        case .deepseek:
            ["com.googlecode.iterm2", "com.apple.Terminal"]
        }
    }

    static func from(raw: String?) -> AgentKind {
        guard let raw else { return .claude }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let exact = AgentKind(rawValue: normalized) { return exact }
        switch normalized {
        case "claude-code", "claude_code", "anthropic": return .claude
        case "openai", "openai-codex": return .codex
        case "open-code", "open_code": return .opencode
        case "gemini-cli", "antigravity": return .gemini
        case "kimi-code", "moonshot": return .kimi
        case "deep-seek", "deepseek-cli": return .deepseek
        default: return .claude
        }
    }
}
