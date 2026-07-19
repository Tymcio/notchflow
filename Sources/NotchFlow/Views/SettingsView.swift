import SwiftUI

@MainActor
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
                Spacer(minLength: 0)
                SettingsSidebarFooter()
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
        } detail: {
            tabContent(for: selectedTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                onDeactivate: deactivateLicense,
                onDeactivateInPolar: deactivateInPolar,
                onDeactivateAgents: deactivateAgents,
                onDeactivateAgentsInPolar: deactivateAgentsInPolar
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
                let key = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
                try await appState.licenseManager.activate(key: key)
                if PolarLicenseClient.looksLikeAgentsKey(key) || appState.licenseStatus.hasAgentsAddon {
                    licenseMessage = loc("Agents addon activated.")
                } else {
                    licenseMessage = loc("License activated.")
                }
            } catch {
                licenseMessage = error.localizedDescription
            }
        }
    }

    private func deactivateLicense() {
        do {
            try appState.licenseManager.deactivate()
            licenseMessage = loc("License removed from this Mac.")
        } catch {
            licenseMessage = error.localizedDescription
        }
    }

    private func deactivateInPolar() {
        Task {
            do {
                try await appState.licenseManager.deactivateInPolar()
                licenseMessage = loc("Activation released in Polar. You can activate the key on another Mac.")
            } catch {
                licenseMessage = error.localizedDescription
            }
        }
    }

    private func deactivateAgents() {
        do {
            try appState.licenseManager.deactivateAgents()
            licenseMessage = loc("Agents addon removed from this Mac.")
        } catch {
            licenseMessage = error.localizedDescription
        }
    }

    private func deactivateAgentsInPolar() {
        Task {
            do {
                try await appState.licenseManager.deactivateAgentsInPolar()
                licenseMessage = loc("Agents activation released in Polar.")
            } catch {
                licenseMessage = error.localizedDescription
            }
        }
    }
}
