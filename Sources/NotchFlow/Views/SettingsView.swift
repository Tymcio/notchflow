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
        NavigationSplitView {
            VStack(spacing: 0) {
                SettingsBrandingHeader()
                List(SettingsTab.allCases, selection: $selectedTab) { tab in
                    Label(tab.title, systemImage: tab.systemImage)
                        .tag(tab)
                }
                .listStyle(.sidebar)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
        } detail: {
            ScrollView {
                tabContent(for: selectedTab)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle(selectedTab.title)
        }
        .frame(minWidth: 640, minHeight: 480)
        .onAppear {
            selectedTab = initialTab
            if licenseKey.isEmpty, let stored = appState.licenseManager.storedLicenseKey {
                licenseKey = stored
            }
        }
    }

    @ViewBuilder
    private func tabContent(for tab: SettingsTab) -> some View {
        switch tab {
        case .general:
            GeneralSettingsTab(
                settings: appState.settings,
                menuBarLayoutManager: appState.menuBarLayoutManager,
                displayManager: appState.displayManager,
                isPremium: appState.isPremium,
                onOpenLicense: { selectedTab = .license }
            )
        case .appearance:
            AppearanceSettingsTab(settings: appState.settings, isPremium: appState.isPremium)
        case .notifications:
            NotificationsSettingsTab(
                settings: appState.settings,
                isPremium: appState.isPremium,
                menuBarLayoutManager: appState.menuBarLayoutManager
            )
        case .license:
            LicenseSettingsTab(
                status: appState.licenseStatus,
                licenseKey: $licenseKey,
                licenseMessage: $licenseMessage,
                onActivate: activateLicense,
                onDeactivate: deactivateLicense
            )
        case .privacy:
            PrivacySettingsTab(settings: appState.settings)
        case .integrations:
            IntegrationsSettingsTab(appState: appState)
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
