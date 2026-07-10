import AppKit
import SwiftUI

struct IntegrationsSettingsTab: View {
    @Bindable var appState: AppState
    @State private var copiedToken = false
    @State private var copiedURL = false
    @State private var apiBaseURL = ""

    var body: some View {
        Form {
            Section {
                Toggle("Włącz lokalne API (Raycast)", isOn: $appState.settings.localAPIEnabled)
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
                    Label("API działa lokalnie na tym Macu", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Text("Wyłączone domyślnie — włącz tylko jeśli używasz integracji Raycast.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Raycast") {
                LabeledContent("Adres API") {
                    HStack {
                        Text(apiBaseURL.isEmpty ? "Uruchom API, aby zobaczyć adres" : apiBaseURL)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(2)
                        Button(copiedURL ? "Skopiowano" : "Kopiuj") {
                            guard !apiBaseURL.isEmpty else { return }
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(apiBaseURL, forType: .string)
                            copiedURL = true
                        }
                        .disabled(apiBaseURL.isEmpty)
                    }
                }

                LabeledContent("Token API") {
                    HStack {
                        Text(APIAuth.token().prefix(12) + "…")
                            .font(.caption.monospaced())
                        Button(copiedToken ? "Skopiowano" : "Kopiuj") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(APIAuth.token(), forType: .string)
                            copiedToken = true
                        }
                    }
                }

                Text("W rozszerzeniu Raycast wystarczy Token API — adres jest odczytywany automatycznie z api.json. Stały port: \(NotchFlowConstants.localAPIPort).")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Link("Zainstaluj rozszerzenie NotchFlow (repo)", destination: NotchFlowConstants.githubURL.appending(path: "tree/main/integrations/raycast/notchflow"))
            }
        }
        .formStyle(.grouped)
        .padding()
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
