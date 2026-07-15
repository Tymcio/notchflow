import AppKit
import SwiftUI

struct NotificationsSettingsTab: View {
    @Bindable var settings: NotchSettings
    let isPremium: Bool
    @ObservedObject var menuBarLayoutManager: MenuBarLayoutManager

    private var ramboxEnabled: Bool {
        !settings.allowedRamboxAggregatorBundleIDs.isEmpty
    }

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
                if settings.appNotificationsEnabled && isPremium, settings.dismissSystemBanners {
                    SettingsFooterCaption("The macOS banner in the corner is closed automatically once the notification appears in the notch.")
                }
            }

            if settings.appNotificationsEnabled && isPremium {
                nativeAppsSection
                ramboxSection
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
    private var nativeAppsSection: some View {
        Section {
            ForEach(NotificationAppCatalog.installedNativeMessagingApps, id: \.bundleID) { app in
                Toggle(isOn: nativeBinding(for: app.bundleID)) {
                    appRow(app: app, subtitle: loc("Installed Mac app"))
                }
            }
        } header: {
            Text(loc("Installed Mac apps"))
        } footer: {
            SettingsFooterCaption("Notifications from native apps installed on your Mac. Separate from the same service running inside Rambox.")
        }
    }

    @ViewBuilder
    private var ramboxSection: some View {
        if !NotificationAppCatalog.installedAggregators.isEmpty {
            Section {
                ForEach(NotificationAppCatalog.installedAggregators, id: \.bundleID) { aggregator in
                    Toggle(isOn: ramboxAggregatorBinding(for: aggregator.bundleID)) {
                        appRow(app: aggregator, subtitle: loc("Web app container"))
                    }
                }

                if ramboxEnabled {
                    ForEach(NotificationAppCatalog.messagingApps, id: \.bundleID) { service in
                        Toggle(isOn: ramboxServiceBinding(for: service.bundleID)) {
                            appRow(app: service, subtitle: loc("Inside Rambox"))
                        }
                    }
                }
            } header: {
                Text(loc("Rambox"))
            } footer: {
                SettingsFooterCaption("Enable Rambox first, then pick which web apps inside it should appear in the notch. WhatsApp in Rambox and native WhatsApp are controlled separately.")
            }
        }
    }

    @ViewBuilder
    private func appRow(app: NotificationAppCatalog.Entry, subtitle: String) -> some View {
        HStack(spacing: 8) {
            CatalogAppIcon(bundleID: app.bundleID)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.localizedName)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func nativeBinding(for bundleID: String) -> Binding<Bool> {
        Binding(
            get: { settings.allowedNativeNotificationBundleIDs.contains(bundleID) },
            set: { enabled in
                updateList(\.allowedNativeNotificationBundleIDs, bundleID: bundleID, enabled: enabled)
            }
        )
    }

    private func ramboxAggregatorBinding(for bundleID: String) -> Binding<Bool> {
        Binding(
            get: { settings.allowedRamboxAggregatorBundleIDs.contains(bundleID) },
            set: { enabled in
                updateList(\.allowedRamboxAggregatorBundleIDs, bundleID: bundleID, enabled: enabled)
            }
        )
    }

    private func ramboxServiceBinding(for bundleID: String) -> Binding<Bool> {
        Binding(
            get: { settings.allowedRamboxServiceBundleIDs.contains(bundleID) },
            set: { enabled in
                updateList(\.allowedRamboxServiceBundleIDs, bundleID: bundleID, enabled: enabled)
            }
        )
    }

    private func updateList(
        _ keyPath: ReferenceWritableKeyPath<NotchSettings, [String]>,
        bundleID: String,
        enabled: Bool
    ) {
        var list = settings[keyPath: keyPath]
        if enabled {
            if !list.contains(bundleID) {
                list.append(bundleID)
            }
        } else {
            list.removeAll { $0 == bundleID }
        }
        settings[keyPath: keyPath] = list
        AppController.appState?.applyNotificationSettings()
    }
}
