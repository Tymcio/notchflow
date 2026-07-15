import AppKit
import SwiftUI

struct NotificationsSettingsTab: View {
    @Bindable var settings: NotchSettings
    let isPremium: Bool
    @ObservedObject var menuBarLayoutManager: MenuBarLayoutManager

    var body: some View {
        SettingsFormContent {
            Section {
                Toggle(loc("Show incoming calls in the island"), isOn: $settings.callsInNotchEnabled)
                    .disabled(!isPremium)
                    .onChange(of: settings.callsInNotchEnabled) { _, _ in
                        AppController.appState?.applyNotificationSettings()
                    }
            } header: {
                Text(loc("Calls in the notch"))
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if !isPremium {
                        SettingsFooterCaption("Calls in the notch require a Premium license.")
                    }
                    SettingsFooterCaption("FaceTime and calls relayed from iPhone appear in the island instead of only as a side banner.")
                }
            }

            Section {
                Toggle(loc("Show notifications from selected apps in the island"), isOn: $settings.appNotificationsEnabled)
                    .disabled(!isPremium)
                    .onChange(of: settings.appNotificationsEnabled) { _, _ in
                        AppController.appState?.applyNotificationSettings()
                    }

                Toggle(loc("Hide message body (show sender only)"), isOn: $settings.hideNotificationBody)
                    .disabled(!settings.appNotificationsEnabled || !isPremium)
                    .onChange(of: settings.hideNotificationBody) { _, _ in
                        AppController.appState?.applyNotificationSettings()
                    }

                Toggle(loc("Close the system banner when shown in the island"), isOn: $settings.dismissSystemBanners)
                    .disabled(!settings.appNotificationsEnabled || !isPremium)
            } header: {
                Text(loc("App notifications"))
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if settings.appNotificationsEnabled && isPremium {
                        if settings.dismissSystemBanners {
                            SettingsFooterCaption("The macOS banner in the corner is closed automatically once the notification appears in the notch.")
                        }
                        SettingsFooterCaption("Using Rambox? Enable Rambox in the list — WhatsApp, Telegram, and MSN notifications go through Rambox, not native apps.")
                    }
                }
            }

            if settings.appNotificationsEnabled && isPremium {
                Section {
                    appPicker
                } header: {
                    Text(loc("Apps"))
                }
            }

            Section {
                if !menuBarLayoutManager.isAccessibilityTrusted {
                    HStack {
                        Button(loc("Grant permission")) {
                            menuBarLayoutManager.requestPermission()
                        }
                        Button(loc("Open System Settings")) {
                            menuBarLayoutManager.openAccessibilitySettings()
                        }
                    }
                }
            } header: {
                Text(loc("Permissions"))
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if menuBarLayoutManager.isAccessibilityTrusted {
                        SettingsFooterCaption("Accessibility is enabled — NotchFlow can read system notification banners.")
                    } else {
                        SettingsFooterCaption("Accessibility permission is required to detect calls and Notification Center alerts.")
                    }
                    SettingsFooterCaption("Notification content is kept in RAM only and is not saved to disk.")
                }
            }
        }
    }

    @ViewBuilder
    private var appPicker: some View {
        ForEach(NotificationHubManager.suggestedApps, id: \.bundleID) { app in
            Toggle(isOn: binding(for: app.bundleID)) {
                HStack(spacing: 8) {
                    CatalogAppIcon(bundleID: app.bundleID)
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
