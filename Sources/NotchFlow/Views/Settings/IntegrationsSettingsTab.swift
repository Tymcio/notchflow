import AppKit
import SwiftUI

@MainActor
struct IntegrationsSettingsTab: View {
    @Bindable var appState: AppState
    @State private var copiedToken = false
    @State private var copiedURL = false
    @State private var apiBaseURL = ""

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
                        Text(appState.settings.localAPIEnabled ? loc("On") : loc("Off"))
                    }

                    AgentConnectionsView(appState: appState)

                    Button(loc("Reveal hooks folder")) {
                        let url = AgentHooksInstaller.hookScriptURL.deletingLastPathComponent()
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }

                    Toggle(loc("Show Claude, Codex, Cursor, and Grok usage"), isOn: $appState.settings.agentUsagePollingEnabled)
                        .onChange(of: appState.settings.agentUsagePollingEnabled) { _, _ in
                            appState.applyAgentUsagePolling()
                        }

                    Text(loc("macOS may ask whether NotchFlow can use “Claude Safe Storage”, “Cursor Safe Storage” or “Grok Bot Safe Storage”. That item is the key to all of that app’s encrypted data on this Mac, not only its login. NotchFlow uses it only to read the login for usage limits and keeps tokens in memory. “Always Allow” stops the question for good; “Allow” asks again next time."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

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
                        Text(loc("Grok Build: session status in the notch. Allow and Deny stay in the terminal. Restart the grok CLI after connecting. Grok Bot shows its weekly limit only."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                } else {
                    Button(loc("Open license activation")) {
                        appState.openLicenseSettings()
                    }
                }
            } header: {
                Text(loc("Agents addon"))
            } footer: {
                Text(loc("Hooks stay on your Mac. Usage limits reuse the Claude, Codex, Cursor, Grok Build, and Grok Bot logins already on this Mac and ask those providers only."))
                    .font(.caption)
            }
        }
        .onAppear {
            refreshAPIInfo()
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
