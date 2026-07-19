import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct GeneralSettingsTab: View {
    @Bindable var settings: NotchSettings
    @ObservedObject var menuBarLayoutManager: MenuBarLayoutManager
    var displayManager: DisplayManager
    var isPremium: Bool
    var onOpenLicense: () -> Void

    @State private var selectedLanguage = LanguageService.current

    var body: some View {
        SettingsFormContent {
            Section {
                Toggle(loc("Launch at login"), isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, enabled in
                        enabled ? LaunchAtLoginService.enable() : LaunchAtLoginService.disable()
                    }
            }

            Section {
                Picker(loc("Language"), selection: $selectedLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .onChange(of: selectedLanguage) { _, newValue in
                    LanguageService.apply(newValue)
                }
            } footer: {
                SettingsFooterCaption("Changing the language restarts NotchFlow.")
            }

            Section {
                HStack(spacing: 10) {
                    Picker(loc("Alert sound"), selection: $settings.timerAlertSoundName) {
                        Text(loc("None")).tag(TimerAlertSound.none)
                        Section(loc("Ringtones")) {
                            ForEach(TimerAlertSound.ringtoneOptions) { option in
                                Text(option.title).tag(option.id)
                            }
                        }
                        Section(loc("System sounds")) {
                            ForEach(TimerAlertSound.systemOptions) { option in
                                Text(option.title).tag(option.id)
                            }
                        }
                    }
                    .onChange(of: settings.timerAlertSoundName) { _, id in
                        TimerAlertSound.play(id)
                    }

                    Button {
                        TimerAlertSound.play(settings.timerAlertSoundName)
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                    }
                    .help(loc("Preview"))
                    .disabled(settings.timerAlertSoundName.isEmpty)
                }
            } header: {
                Text(loc("Timer"))
            } footer: {
                SettingsFooterCaption("Same tones as the Clock app. Plays until you dismiss the finished timer.")
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
                Text(loc("Notch hover"))
            } footer: {
                if menuBarLayoutManager.isAccessibilityTrusted {
                    SettingsFooterCaption("NotchFlow tracks the cursor globally (requires Accessibility).")
                } else {
                    SettingsFooterCaption("Without Accessibility, a fallback zone along the top edge is used. For the fastest response, enable NotchFlow in System Settings → Privacy → Accessibility.")
                }
            }

            Section {
                Toggle(loc("Avoid covering the app menu"), isOn: $settings.avoidMenuOverlap)
                    .onChange(of: settings.avoidMenuOverlap) { _, _ in
                        menuBarLayoutManager.refresh()
                    }

                if settings.avoidMenuOverlap, !menuBarLayoutManager.isAccessibilityTrusted {
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
                Text(loc("App menu"))
            } footer: {
                if settings.avoidMenuOverlap {
                    if menuBarLayoutManager.isAccessibilityTrusted {
                        SettingsFooterCaption("NotchFlow narrows the left idle wing when the active app's menu bar reaches the notch.")
                    } else {
                        SettingsFooterCaption("Accessibility permission is required to detect the app menu position.")
                    }
                }
            }

            Section {
                if isPremium {
                    if settings.hiddenAppBundleIDs.isEmpty {
                        Text(loc("No apps selected."))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(settings.hiddenAppBundleIDs, id: \.self) { bundleID in
                            HiddenAppRow(bundleID: bundleID) {
                                removeHiddenApp(bundleID)
                            }
                        }
                    }

                    Button(loc("Add app…")) {
                        pickApplication()
                    }
                }
            } header: {
                Text(loc("Hide island for apps"))
            } footer: {
                if isPremium {
                    SettingsFooterCaption("The island won't appear when a selected app is active.")
                } else {
                    SettingsFooterCaption("Hiding the island for selected apps is a Premium feature — activate your license below.")
                }
            }

            Section {
                Button(loc("Enter license key…"), action: onOpenLicense)
            } header: {
                Text(loc("Premium"))
            } footer: {
                if LicenseMode.current.isEnforced {
                    SettingsFooterCaption("Camera mirror, themes, larger clipboard, and more require an active license.")
                } else {
                    SettingsFooterCaption("Beta period — all Premium features are unlocked without a key.")
                }
            }
        }
    }

    private func removeHiddenApp(_ bundleID: String) {
        settings.hiddenAppBundleIDs.removeAll { $0 == bundleID }
        displayManager.refreshHideState()
    }

    private func pickApplication() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.prompt = loc("Add")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        guard !settings.hiddenAppBundleIDs.contains(bundleID) else { return }
        settings.hiddenAppBundleIDs.append(bundleID)
        displayManager.refreshHideState()
    }
}

private struct HiddenAppRow: View {
    let bundleID: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "app.fill")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(appName)
                    .font(.body)
                Text(bundleID)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red.opacity(0.85))
            .help(loc("Remove from list"))
        }
    }

    private var appName: String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: url) {
            return bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundleID
        }
        return bundleID
    }

    private var appIcon: NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

