import AppKit
import SwiftUI

@MainActor
struct AgentsTabView: View {
    @Bindable var appState: AppState

    private var sessions: [AgentSession] {
        appState.agentSessionManager.sessions
    }

    private var accent: Color {
        appState.settings.selectedTheme.accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !appState.hasAgentsAddon {
                lockedState
            } else if sessions.isEmpty {
                emptyState
            } else {
                sessionList
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var lockedState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(loc("Agents addon"), systemImage: "lock.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(IslandStyle.primaryText)
            Text(loc("Monitor Claude Code, Codex, Cursor, and more from the notch. One-time €14.90."))
                .font(.caption)
                .foregroundStyle(IslandStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            AgentsIslandButton(
                title: loc("Open license activation"),
                systemImage: "key.fill",
                style: .accent(accent)
            ) {
                appState.openLicenseSettings()
            }
        }
        .padding(.top, 4)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(loc("No active agent sessions"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(IslandStyle.primaryText)
            Text(loc("Connect agents in Settings → Integrations, then run Cursor Agent or Claude Code."))
                .font(.caption)
                .foregroundStyle(IslandStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            AgentsIslandButton(
                title: loc("Open Integrations"),
                systemImage: "puzzlepiece.extension.fill",
                style: .accent(accent)
            ) {
                appState.openIntegrationsSettings()
            }
        }
        .padding(.top, 4)
    }

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(loc("Active sessions"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(IslandStyle.secondaryText)
                Spacer()
                Button {
                    appState.agentSessionManager.clearFinished()
                } label: {
                    Text(loc("Clear finished"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(IslandStyle.secondaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
            }

            ForEach(sessions) { session in
                sessionRow(session)
            }
        }
    }

    @ViewBuilder
    private func sessionRow(_ session: AgentSession) -> some View {
        let needsAttention = session.needsAttention
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: session.agent.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(needsAttention ? Color.orange : IslandStyle.primaryText)
                    .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.agent.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(IslandStyle.primaryText)
                        .lineLimit(1)
                    Text(phaseLabel(session.phase))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(needsAttention ? Color.orange : IslandStyle.secondaryText)
                }

                Spacer(minLength: 0)

                Button {
                    appState.agentSessionManager.jump(to: session)
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(IslandStyle.secondaryText)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help(loc("Jump to agent"))
            }

            if let permission = session.permission {
                Text(shortDetail(permission.summary.isEmpty ? permission.toolName : permission.summary))
                    .font(.caption)
                    .foregroundStyle(IslandStyle.primaryText.opacity(0.9))
                    .lineLimit(2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.orange.opacity(0.12))
                    )

                HStack(spacing: 8) {
                    AgentsIslandButton(
                        title: loc("Deny"),
                        systemImage: "xmark",
                        style: .destructive,
                        expands: true
                    ) {
                        appState.agentSessionManager.decidePermission(id: permission.id, decision: .deny)
                    }
                    AgentsIslandButton(
                        title: loc("Allow"),
                        systemImage: "checkmark",
                        style: .success,
                        expands: true
                    ) {
                        appState.agentSessionManager.decidePermission(id: permission.id, decision: .allow)
                    }
                }
            } else if let question = session.question {
                Text(question.prompt)
                    .font(.caption)
                    .foregroundStyle(IslandStyle.primaryText.opacity(0.9))
                    .lineLimit(3)
                FlowQuestionButtons(options: question.options, accent: accent) { optionID in
                    appState.agentSessionManager.answerQuestion(id: question.id, optionID: optionID)
                }
            } else if !session.detail.isEmpty {
                Text(shortDetail(session.detail))
                    .font(.caption2)
                    .foregroundStyle(IslandStyle.secondaryText)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(needsAttention ? 0.09 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(needsAttention ? Color.orange.opacity(0.35) : Color.clear, lineWidth: 1)
        )
    }

    private func phaseLabel(_ phase: AgentSessionPhase) -> String {
        switch phase {
        case .running: loc("Running")
        case .waitingPermission: loc("Needs approval")
        case .waitingQuestion: loc("Waiting")
        case .done: loc("Done")
        case .error: loc("Error")
        }
    }

    /// Avoid dumping full absolute paths into the compact island card.
    private func shortDetail(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let colon = trimmed.firstIndex(of: ":") {
            let tool = trimmed[..<colon].trimmingCharacters(in: .whitespaces)
            let rest = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if rest.hasPrefix("/") {
                return "\(tool): \(URL(fileURLWithPath: String(rest)).lastPathComponent)"
            }
        }
        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed).lastPathComponent
        }
        return trimmed
    }
}

// MARK: - Island buttons

private enum AgentsIslandButtonStyle {
    case accent(Color)
    case success
    case destructive
    case quiet

    var foreground: Color {
        switch self {
        case .accent, .success: Color.black.opacity(0.88)
        case .destructive: .white
        case .quiet: IslandStyle.primaryText
        }
    }

    @ViewBuilder
    var fill: some View {
        switch self {
        case .accent(let color):
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.95), color.opacity(0.75)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        case .success:
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.32, green: 0.82, blue: 0.48),
                            Color(red: 0.18, green: 0.68, blue: 0.36),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        case .destructive:
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.92, green: 0.34, blue: 0.34),
                            Color(red: 0.78, green: 0.18, blue: 0.22),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        case .quiet:
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.10))
        }
    }
}

private struct AgentsIslandButton: View {
    let title: String
    let systemImage: String
    let style: AgentsIslandButtonStyle
    var expands: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .bold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(style.foreground)
            .frame(maxWidth: expands ? .infinity : nil)
            .padding(.horizontal, expands ? 12 : 14)
            .padding(.vertical, 8)
            .background { style.fill }
        }
        .buttonStyle(.plain)
    }
}

private struct FlowQuestionButtons: View {
    let options: [AgentQuestionOption]
    let accent: Color
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                Button {
                    onSelect(option.id)
                } label: {
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.85))
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(accent.opacity(0.9)))
                        Text(option.label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(IslandStyle.primaryText)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
