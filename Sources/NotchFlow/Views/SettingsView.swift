import SwiftUI

struct SettingsView: View {
    @Bindable var appState: AppState
    let initialTab: SettingsTab
    @State private var licenseKey = ""
    @State private var licenseMessage = ""
    @State private var selectedTab: SettingsTab

    init(appState: AppState, initialTab: SettingsTab = .general) {
        self.appState = appState
        self.initialTab = initialTab
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsTab(
                settings: appState.settings,
                menuBarLayoutManager: appState.menuBarLayoutManager,
                onOpenLicense: {
                    selectedTab = .license
                }
            )
                .tabItem { Label("Ogólne", systemImage: "gearshape") }
                .tag(SettingsTab.general)

            AppearanceSettingsTab(settings: appState.settings, isPremium: appState.isPremium)
                .tabItem { Label("Wygląd", systemImage: "paintbrush") }
                .tag(SettingsTab.appearance)

            LicenseSettingsTab(
                status: appState.licenseStatus,
                licenseKey: $licenseKey,
                licenseMessage: $licenseMessage,
                onActivate: activateLicense,
                onDeactivate: deactivateLicense
            )
            .tabItem { Label("Licencja", systemImage: "key") }
            .tag(SettingsTab.license)

            PrivacySettingsTab(settings: appState.settings)
                .tabItem { Label("Prywatność", systemImage: "hand.raised") }
                .tag(SettingsTab.privacy)

            IntegrationsSettingsTab(appState: appState)
                .tabItem { Label("Integracje", systemImage: "link") }
                .tag(SettingsTab.integrations)
        }
        .frame(width: 520, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            selectedTab = initialTab
            if licenseKey.isEmpty, let stored = appState.licenseManager.storedLicenseKey {
                licenseKey = stored
            }
        }
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
