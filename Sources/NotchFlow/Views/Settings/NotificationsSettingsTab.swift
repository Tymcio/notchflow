import AppKit
import SwiftUI

struct NotificationsSettingsTab: View {
    @Bindable var settings: NotchSettings
    let isPremium: Bool
    @ObservedObject var menuBarLayoutManager: MenuBarLayoutManager

    var body: some View {
        Form {
            Section("Połączenia w notchu") {
                Toggle("Pokazuj połączenia przychodzące w wyspie", isOn: $settings.callsInNotchEnabled)
                    .disabled(!isPremium)
                    .onChange(of: settings.callsInNotchEnabled) { _, _ in
                        AppController.appState?.applyNotificationSettings()
                    }

                if !isPremium {
                    Text("Połączenia w notchu wymagają licencji Premium.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("FaceTime i połączenia przekazywane z iPhone'a pojawią się w wyspie zamiast tylko jako banner z boku.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Powiadomienia aplikacji") {
                Toggle("Pokazuj powiadomienia wybranych aplikacji w wyspie", isOn: $settings.appNotificationsEnabled)
                    .disabled(!isPremium)
                    .onChange(of: settings.appNotificationsEnabled) { _, _ in
                        AppController.appState?.applyNotificationSettings()
                    }

                Toggle("Ukryj treść wiadomości (pokaż tylko nadawcę)", isOn: $settings.hideNotificationBody)
                    .disabled(!settings.appNotificationsEnabled || !isPremium)
                    .onChange(of: settings.hideNotificationBody) { _, _ in
                        AppController.appState?.applyNotificationSettings()
                    }

                if settings.appNotificationsEnabled && isPremium {
                    Text("Używasz Rambox? Włącz Rambox na liście — powiadomienia z WhatsApp, Telegram i MSN idą przez Rambox, nie przez natywne apki.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    appPicker
                }
            }

            Section("Uprawnienia") {
                if menuBarLayoutManager.isAccessibilityTrusted {
                    Text("Dostępność jest włączona — NotchFlow może odczytywać bannery powiadomień systemowych.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Wymagane uprawnienie Dostępności, aby wykrywać połączenia i powiadomienia z Notification Center.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button("Nadaj uprawnienie") {
                            menuBarLayoutManager.requestPermission()
                        }
                        Button("Otwórz ustawienia systemowe") {
                            menuBarLayoutManager.openAccessibilitySettings()
                        }
                    }
                }

                Text("Treść powiadomień jest trzymana wyłącznie w pamięci RAM i nie jest zapisywana na dysk.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    @ViewBuilder
    private var appPicker: some View {
        ForEach(NotificationHubManager.suggestedApps, id: \.bundleID) { app in
            Toggle(isOn: binding(for: app.bundleID)) {
                HStack(spacing: 8) {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable()
                            .frame(width: 18, height: 18)
                    }
                    Text(app.name)
                }
            }
        }
    }

    private func binding(for bundleID: String) -> Binding<Bool> {
        Binding(
            get: { settings.allowedNotificationBundleIDs.contains(bundleID) },
            set: { enabled in
                if enabled {
                    if !settings.allowedNotificationBundleIDs.contains(bundleID) {
                        settings.allowedNotificationBundleIDs.append(bundleID)
                    }
                } else {
                    settings.allowedNotificationBundleIDs.removeAll { $0 == bundleID }
                }
                AppController.appState?.applyNotificationSettings()
            }
        )
    }
}
