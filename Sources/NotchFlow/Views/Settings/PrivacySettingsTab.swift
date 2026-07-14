import SwiftUI

struct PrivacySettingsTab: View {
    @Bindable var settings: NotchSettings

    var body: some View {
        SettingsFormContent {
            Section {
                Toggle(loc("Monitor clipboard"), isOn: $settings.clipboardMonitoringEnabled)
                    .onChange(of: settings.clipboardMonitoringEnabled) { _, enabled in
                        AppController.appState?.setClipboardMonitoringEnabled(enabled)
                    }
            } footer: {
                SettingsFooterCaption("Stores recent copied text and links locally. Passwords and concealed pasteboard entries are skipped. Off by default.")
            }

            Section {
                Toggle(loc("Allow URL scheme automation (notchflow://)"), isOn: $settings.urlSchemeAutomationEnabled)
            } footer: {
                SettingsFooterCaption("When disabled, other apps cannot control NotchFlow via notchflow://. Camera mirror requires additional confirmation.")
            }

            Section {
                Toggle(loc("Share track titles for lyrics lookup"), isOn: $settings.lyricsSharingEnabled)
            } footer: {
                SettingsFooterCaption("Sends title and artist to lrclib.net only while playing and only when enabled.")
            }

            Section {
                Link(loc("Security and privacy policy"), destination: NotchFlowConstants.websiteURL.appending(path: "security"))
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    SettingsFooterCaption("NotchFlow does not collect telemetry in version 1.0.")
                    SettingsFooterCaption("Network access is used for license verification, updates, and optional local API.")
                }
            }
        }
    }
}
