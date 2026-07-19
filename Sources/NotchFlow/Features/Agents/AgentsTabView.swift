import AppKit
import SwiftUI

@MainActor
struct AgentsTabView: View {
    @Bindable var appState: AppState
    @State private var installMessage = ""
    @State private var isInstalling = false

    private var sessions: [AgentSession] {
        appState.agentSessionManager.sessions
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
        VStack(alignment: .leading, spacing: 8) {
            Label(loc("Agents addon"), systemImage: "lock.fill")
                .font(.system(size: 12, weight: .semibold))
            Text(loc("Monitor Claude Code, Codex, Cursor, and more from the notch. One-time €14.90."))
                .font(.caption)
                .foregroundStyle(IslandStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button(loc("Open license activation")) {
                appState.openLicenseSettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.top, 4)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loc("No active agent sessions"))
                .font(.system(size: 12, weight: .semibold))
            Text(loc("Enable hooks so Claude Code and other agents appear here. Local API must stay on."))
                .font(.caption)
                .foregroundStyle(IslandStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button(isInstalling ? loc("Installing…") : loc("Enable Agents")) {
                    installHooks()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isInstalling)

                if !sessions.isEmpty {
                    Button(loc("Clear finished")) {
                        appState.agentSessionManager.clearFinished()
                    }
                    .controlSize(.small)
                }
            }

            if !installMessage.isEmpty {
                Text(installMessage)
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
        .padding(.top, 4)
    }

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(loc("Agents"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(IslandStyle.secondaryText)
                Spacer()
                Button(loc("Enable Agents")) {
                    installHooks()
                }
                .controlSize(.mini)
                Button(loc("Clear finished")) {
                    appState.agentSessionManager.clearFinished()
                }
                .controlSize(.mini)
            }

            ForEach(sessions) { session in
                sessionRow(session)
            }

            if !installMessage.isEmpty {
                Text(installMessage)
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
    }

    @ViewBuilder
    private func sessionRow(_ session: AgentSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: session.agent.systemImage)
                    .foregroundStyle(session.phase == .waitingPermission ? Color.orange : IslandStyle.primaryText)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text("\(session.agent.displayName) · \(phaseLabel(session.phase))")
                        .font(.caption2)
                        .foregroundStyle(IslandStyle.secondaryText)
                }
                Spacer(minLength: 0)
                Button {
                    appState.agentSessionManager.jump(to: session)
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.plain)
                .help(loc("Jump to agent"))
            }

            if !session.detail.isEmpty {
                Text(session.detail)
                    .font(.caption2)
                    .foregroundStyle(IslandStyle.secondaryText)
                    .lineLimit(2)
            }

            if let permission = session.permission {
                Text(permission.summary)
                    .font(.caption)
                    .lineLimit(3)
                HStack(spacing: 8) {
                    Button(loc("Deny")) {
                        appState.agentSessionManager.decidePermission(id: permission.id, decision: .deny)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.small)

                    Button(loc("Allow")) {
                        appState.agentSessionManager.decidePermission(id: permission.id, decision: .allow)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.small)
                }
            }

            if let question = session.question {
                Text(question.prompt)
                    .font(.caption)
                    .lineLimit(3)
                FlowQuestionButtons(options: question.options) { optionID in
                    appState.agentSessionManager.answerQuestion(id: question.id, optionID: optionID)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.06))
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

    private func installHooks() {
        isInstalling = true
        installMessage = ""
        Task {
            do {
                if !appState.settings.localAPIEnabled {
                    appState.settings.localAPIEnabled = true
                    try await appState.localAPIServer.start(appState: appState)
                }
                _ = try APIAuth.token()
                let url = try AgentHooksInstaller.install()
                installMessage = locFormat("Hooks installed at %@", url.path)
            } catch {
                installMessage = error.localizedDescription
            }
            isInstalling = false
        }
    }
}

private struct FlowQuestionButtons: View {
    let options: [AgentQuestionOption]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                Button("⌘\(index + 1)  \(option.label)") {
                    onSelect(option.id)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}
