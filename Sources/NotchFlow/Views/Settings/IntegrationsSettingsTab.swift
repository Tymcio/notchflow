import AppKit
import SwiftUI

@MainActor
struct IntegrationsSettingsTab: View {
    @Bindable var appState: AppState
    @State private var copiedToken = false
    @State private var copiedURL = false
    @State private var apiBaseURL = ""
    @State private var agentsMessage = ""
    @State private var isInstallingAgents = false

    private var agentsSetup: AgentHooksInstaller.SetupStatus {
        AgentHooksInstaller.currentStatus(localAPIEnabled: appState.settings.localAPIEnabled)
    }

    var body: some View {
        SettingsFormContent {
            Section {
                Toggle(loc("Enable local API (Raycast)"), isOn: $appState.settings.localAPIEnabled)
                    .onChange(of: appState.settings.localAPIEnabled) { _, enabled in
                        Task {
                            if enabled {
                                do {
                                    try await appState.localAPIServer.start(appState: appState)
                                } catch {
                                    NotchFlowLog.api.error("Failed to start local API: \(error.localizedDescription, privacy: .public)")
                                }
                            } else {
                                appState.localAPIServer.stop()
                            }
                            refreshAPIInfo()
                        }
                    }

                if appState.settings.localAPIEnabled {
                    Label(loc("API running locally on this Mac"), systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    LocText("Off by default — enable only if you use Raycast integration.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(loc("Raycast")) {
                LabeledContent(loc("API address")) {
                    HStack {
                        Text(apiBaseURL.isEmpty ? loc("Start API to see address") : apiBaseURL)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(2)
                        Button(copiedURL ? loc("Copied") : loc("Copy")) {
                            guard !apiBaseURL.isEmpty else { return }
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(apiBaseURL, forType: .string)
                            copiedURL = true
                        }
                        .disabled(apiBaseURL.isEmpty)
                    }
                }

                LabeledContent(loc("API Token")) {
                    HStack {
                        Text(APIAuth.resolvedToken().prefix(12) + "…")
                            .font(.caption.monospaced())
                        Button(copiedToken ? loc("Copied") : loc("Copy")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(APIAuth.resolvedToken(), forType: .string)
                            copiedToken = true
                        }
                    }
                }

                Text(locFormat("In the Raycast extension, only the API Token is needed — the address is read automatically from api.json. Fixed port: %lld.", NotchFlowConstants.localAPIPort))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Link(loc("Install NotchFlow extension (repo)"), destination: NotchFlowConstants.githubURL.appending(path: "tree/main/integrations/raycast/notchflow"))
            }

            Section {
                LocText("Optional coding addon — monitor agents in the notch. Separate from Premium (€14.90).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                LabeledContent(loc("Addon status")) {
                    Text(appState.hasAgentsAddon ? loc("Unlocked") : loc("Locked"))
                        .fontWeight(.medium)
                }

                if appState.hasAgentsAddon {
                    LabeledContent(loc("Local API")) {
                        Text(agentsSetup.localAPIEnabled ? loc("On") : loc("Off"))
                    }
                    LabeledContent("Claude Code") {
                        Text(agentsSetup.claudeHooksInstalled ? loc("Connected") : loc("Not connected"))
                    }
                    LabeledContent("Cursor") {
                        Text(agentsSetup.cursorHooksInstalled ? loc("Connected") : loc("Not connected"))
                    }

                    Button(isInstallingAgents ? loc("Connecting…") : loc("Connect agents (Claude + Cursor)")) {
                        installAgents()
                    }
                    .disabled(isInstallingAgents)

                    Button(loc("Reveal hooks folder")) {
                        let url = AgentHooksInstaller.hookScriptURL.deletingLastPathComponent()
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(loc("How to connect Cursor"))
                            .font(.headline)
                        Text(loc("1. Click Connect agents — writes ~/.cursor/hooks.json and enables Local API."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(loc("2. Fully quit Cursor (Cmd+Q) and open it again."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(loc("3. Start Agent Chat — live status appears in the notch and clears when the agent finishes."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(loc("Claude Code: Allow / Deny in the notch. Cursor: keeps its own Skip/Run — the notch pulses on likely consent moments; tap to jump (no auto-focus)."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)

                    if !agentsMessage.isEmpty {
                        Text(agentsMessage)
                            .font(.caption)
                            .foregroundStyle(.green)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Button(loc("Open license activation")) {
                        appState.openLicenseSettings()
                    }
                }
            } header: {
                Text(loc("Agents addon"))
            } footer: {
                Text(loc("Hooks stay on your Mac. No agent code or prompts are sent to NotchFlow servers."))
                    .font(.caption)
            }
        }
        .onAppear {
            refreshAPIInfo()
        }
    }

    private func installAgents() {
        isInstallingAgents = true
        agentsMessage = ""
        Task {
            do {
                if !appState.settings.localAPIEnabled {
                    appState.settings.localAPIEnabled = true
                    try await appState.localAPIServer.start(appState: appState)
                }
                _ = try APIAuth.token()
                let url = try AgentHooksInstaller.install()
                refreshAPIInfo()
                agentsMessage = locFormat("Hooks installed. Restart Cursor, then use Agent Chat. Folder: %@", url.path)
            } catch {
                agentsMessage = error.localizedDescription
            }
            isInstallingAgents = false
        }
    }

    private func refreshAPIInfo() {
        let apiFile = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("NotchFlow/api.json")
        guard let data = try? Data(contentsOf: apiFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let baseURL = json["baseURL"] as? String else {
            apiBaseURL = ""
            return
        }
        apiBaseURL = baseURL
    }
}
