import SwiftUI

/// Settings → Integrations → Agents: detected coding agents, a toggle per agent, and
/// Connect / Disconnect for NotchFlow's hooks.
@MainActor
struct AgentConnectionsView: View {
    @Bindable var appState: AppState
    @State private var detected: [AgentKind] = []
    @State private var connected: Set<AgentKind> = []
    @State private var message = ""
    @State private var messageIsError = false
    @State private var isWorking = false

    /// Detected agents, plus any already connected (so they can be disconnected).
    private var listedAgents: [AgentKind] {
        AgentKind.connectableAgents.filter { detected.contains($0) || connected.contains($0) }
    }

    private var selectedAgents: Set<AgentKind> {
        Set(listedAgents.filter { !appState.settings.deselectedAgentHooks.contains($0.rawValue) })
    }

    var body: some View {
        Group {
            if listedAgents.isEmpty {
                LocText("No supported coding agents found on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(listedAgents) { agent in
                AgentConnectionRow(agent: agent, isConnected: connected.contains(agent), isSelected: selection(for: agent))
            }
            buttons
            if !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(messageIsError ? Color.red : Color.green)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear(perform: refresh)
    }

    private var buttons: some View {
        HStack {
            Button(isWorking ? loc("Connecting…") : loc("Connect agents")) {
                connect()
            }
            .disabled(isWorking || listedAgents.isEmpty)
            Button(loc("Disconnect")) {
                disconnect()
            }
            .disabled(isWorking || connected.isEmpty)
        }
    }

    private func selection(for agent: AgentKind) -> Binding<Bool> {
        Binding(
            get: { !appState.settings.deselectedAgentHooks.contains(agent.rawValue) },
            set: { isOn in
                var deselected = Set(appState.settings.deselectedAgentHooks)
                if isOn {
                    deselected.remove(agent.rawValue)
                } else {
                    deselected.insert(agent.rawValue)
                }
                appState.settings.deselectedAgentHooks = deselected.sorted()
            }
        )
    }

    private func refresh() {
        detected = AgentDetection.detectedAgents()
        connected = AgentHooksInstaller.currentStatus(localAPIEnabled: appState.settings.localAPIEnabled).connectedAgents
    }

    private func connect() {
        let agents = selectedAgents
        guard !agents.isEmpty else {
            show(loc("Select at least one agent."), isError: true)
            return
        }
        isWorking = true
        Task {
            do {
                try await enableLocalAPI()
                try AgentHooksInstaller.install(enabledAgents: agents)
                show(connectedMessage(for: agents), isError: false)
            } catch {
                show(error.localizedDescription, isError: true)
            }
            refresh()
            isWorking = false
        }
    }

    private func enableLocalAPI() async throws {
        if !appState.settings.localAPIEnabled {
            appState.settings.localAPIEnabled = true
            try await appState.localAPIServer.start(appState: appState)
        }
        _ = try APIAuth.token()
    }

    private func connectedMessage(for agents: Set<AgentKind>) -> String {
        let names = AgentKind.connectableAgents.filter { agents.contains($0) }.map(\.displayName)
        var text = locFormat("Connected: %@. Restart running agents so they load the hooks.", names.joined(separator: ", "))
        if agents.contains(.codex) {
            text += " " + loc("Approve the NotchFlow hook once with /hooks in Codex.")
        }
        return text
    }

    private func disconnect() {
        do {
            try AgentHooksInstaller.uninstall()
            show(loc("Disconnected. NotchFlow’s hooks were removed from each agent."), isError: false)
        } catch {
            show(error.localizedDescription, isError: true)
        }
        refresh()
    }

    private func show(_ text: String, isError: Bool) {
        message = text
        messageIsError = isError
    }
}

private struct AgentConnectionRow: View {
    let agent: AgentKind
    let isConnected: Bool
    @Binding var isSelected: Bool

    var body: some View {
        Toggle(isOn: $isSelected) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Label(agent.displayName, systemImage: agent.systemImage)
                    Spacer()
                    Text(isConnected ? loc("Connected") : loc("Not connected"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(notes, id: \.self) { note in
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var notes: [String] {
        var notes: [String] = []
        switch agent.hookCapability {
        case .answersInNotch:
            notes.append(loc("Allow / Deny in the notch"))
        case .statusOnly, nil:
            notes.append(loc("Status only — answer prompts in the agent"))
        }
        if agent == .codex {
            notes.append(loc("Approve the NotchFlow hook once with /hooks in Codex."))
        }
        return notes
    }
}
