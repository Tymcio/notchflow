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
