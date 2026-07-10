import SwiftUI

struct SettingsView: View {
    @Bindable var appState: AppState
    @State private var licenseKey = ""
    @State private var licenseMessage = ""

    var body: some View {
        TabView {
            GeneralSettingsTab(settings: appState.settings)
                .tabItem { Label("Ogólne", systemImage: "gearshape") }

            AppearanceSettingsTab(settings: appState.settings, isPremium: appState.isPremium)
                .tabItem { Label("Wygląd", systemImage: "paintbrush") }

            LicenseSettingsTab(
                status: appState.licenseStatus,
                licenseKey: $licenseKey,
                licenseMessage: $licenseMessage,
                onActivate: activateLicense,
                onDeactivate: deactivateLicense
            )
            .tabItem { Label("Licencja", systemImage: "key") }

            PrivacySettingsTab(settings: appState.settings)
                .tabItem { Label("Prywatność", systemImage: "hand.raised") }

            IntegrationsSettingsTab(appState: appState)
                .tabItem { Label("Integracje", systemImage: "link") }
        }
        .frame(width: 520, height: 460)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func activateLicense() {
        Task {
            do {
                try await appState.licenseManager.activate(key: licenseKey.trimmingCharacters(in: .whitespacesAndNewlines))
                licenseMessage = "Licencja została aktywowana."
            } catch {
                licenseMessage = error.localizedDescription
            }
        }
    }

    private func deactivateLicense() {
        do {
            try appState.licenseManager.deactivate()
            licenseMessage = "Licencja została usunięta z tego Maca."
        } catch {
            licenseMessage = error.localizedDescription
        }
    }
}

struct GeneralSettingsTab: View {
    @Bindable var settings: NotchSettings

    var body: some View {
        Form {
            Toggle("Uruchamiaj przy logowaniu", isOn: $settings.launchAtLogin)
                .onChange(of: settings.launchAtLogin) { _, enabled in
                    enabled ? LaunchAtLoginService.enable() : LaunchAtLoginService.disable()
                }

            #if canImport(Sparkle)
            if SparkleUpdaterController.shared.isConfigured {
                Button("Sprawdź aktualizacje") {
                    SparkleUpdaterController.shared.checkForUpdates()
                }
            } else {
                Text("Aktualizacje Sparkle są wyłączone w lokalnym buildzie.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            #endif
        }
        .padding()
    }
}

struct AppearanceSettingsTab: View {
    @Bindable var settings: NotchSettings
    let isPremium: Bool

    var body: some View {
        Form {
            Picker("Motyw", selection: $settings.selectedTheme) {
                ForEach(IslandTheme.allCases) { theme in
                    Text(theme.title).tag(theme)
                }
            }
            .disabled(!isPremium && settings.selectedTheme != .system)

            if isPremium {
                HStack {
                    Text("Szerokość wyspy")
                    Slider(value: $settings.customIslandWidth, in: 280...420)
                }
                HStack {
                    Text("Wysokość wyspy")
                    Slider(value: $settings.customIslandHeight, in: 120...200)
                }
            } else {
                Text("Premium odblokowuje własny rozmiar wyspy i motywy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

struct LicenseSettingsTab: View {
    let status: LicenseStatus
    @Binding var licenseKey: String
    @Binding var licenseMessage: String
    let onActivate: () -> Void
    let onDeactivate: () -> Void

    var body: some View {
        Form {
            LabeledContent("Status") {
                Text(status.isPremium ? localizedTier(status.tier) : "Darmowa")
            }

            SecureField("Klucz licencyjny", text: $licenseKey)
            HStack {
                Button("Aktywuj", action: onActivate)
                Button("Dezaktywuj", role: .destructive, action: onDeactivate)
            }

            if !licenseMessage.isEmpty {
                Text(licenseMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Link("Kup Premium na notchflow.eu", destination: NotchFlowConstants.websiteURL.appending(path: "pricing"))
        }
        .padding()
    }

    private func localizedTier(_ tier: LicenseTier) -> String {
        switch tier {
        case .free: "Darmowa"
        case .annual: "Roczna"
        case .lifetime: "Dożywotnia"
        }
    }
}

struct PrivacySettingsTab: View {
    @Bindable var settings: NotchSettings

    var body: some View {
        Form {
            Toggle("Monitoruj schowek", isOn: $settings.clipboardMonitoringEnabled)
                .onChange(of: settings.clipboardMonitoringEnabled) { _, enabled in
                    AppController.appState?.clipboardManager.setMonitoringEnabled(enabled)
                }
            Text("Historia schowka jest przechowywana lokalnie. Domyślnie wyłączona.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("NotchFlow nie zbiera telemetrii w wersji 1.0.")
            Text("Dostęp do sieci służy wyłącznie weryfikacji licencji, aktualizacjom i opcjonalnemu API lokalnemu.")
            Link("Polityka bezpieczeństwa i prywatności", destination: NotchFlowConstants.websiteURL.appending(path: "security"))
        }
        .padding()
    }
}

struct IntegrationsSettingsTab: View {
    @Bindable var appState: AppState
    @State private var copied = false

    var body: some View {
        Form {
            Toggle("Włącz lokalne API (Raycast)", isOn: $appState.settings.localAPIEnabled)
                .onChange(of: appState.settings.localAPIEnabled) { _, enabled in
                    Task {
                        if enabled {
                            try? await appState.localAPIServer.start(appState: appState)
                        } else {
                            appState.localAPIServer.stop()
                        }
                    }
                }

            LabeledContent("Token API") {
                HStack {
                    Text(APIAuth.token().prefix(12) + "…")
                        .font(.caption.monospaced())
                    Button(copied ? "Skopiowano" : "Kopiuj") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(APIAuth.token(), forType: .string)
                        copied = true
                    }
                }
            }

            Text("Skonfiguruj rozszerzenie Raycast dla NotchFlow, używając adresu z ~/Library/Application Support/NotchFlow/api.json oraz tego tokenu.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Link("Otwórz historię schowka Raycast", destination: URL(string: "raycast://extensions/raycast/clipboard-history")!)
        }
        .padding()
    }
}

import AppKit
