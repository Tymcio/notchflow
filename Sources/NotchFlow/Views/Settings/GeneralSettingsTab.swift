import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct GeneralSettingsTab: View {
    @Bindable var settings: NotchSettings
    @ObservedObject var menuBarLayoutManager: MenuBarLayoutManager
    var displayManager: DisplayManager
    var isPremium: Bool
    var onOpenLicense: () -> Void

    var body: some View {
        Form {
            Toggle("Uruchamiaj przy logowaniu", isOn: $settings.launchAtLogin)
                .onChange(of: settings.launchAtLogin) { _, enabled in
                    enabled ? LaunchAtLoginService.enable() : LaunchAtLoginService.disable()
                }

            Section("Najechanie na notch") {
                if menuBarLayoutManager.isAccessibilityTrusted {
                    Text("NotchFlow wykrywa kursor globalnie (wymaga Dostępności).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Bez Dostępności działa tryb zapasowy nad górną krawędzią ekranu. Dla najszybszej reakcji włącz NotchFlow w Ustawienia → Prywatność → Dostępność.")
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
            }

            Section("Menu aplikacji") {
                Toggle("Unikaj zasłaniania menu aplikacji", isOn: $settings.avoidMenuOverlap)
                    .onChange(of: settings.avoidMenuOverlap) { _, _ in
                        menuBarLayoutManager.refresh()
                    }

                if settings.avoidMenuOverlap {
                    if menuBarLayoutManager.isAccessibilityTrusted {
                        Text("NotchFlow zwęża lewe skrzydełko wyspy idle, gdy menu aktywnej aplikacji podchodzi pod notch.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Wymagane uprawnienie Dostępności, aby wykrywać pozycję menu aplikacji.")
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
                }
            }

            Section("Ukryj wyspę dla aplikacji") {
                if isPremium {
                    Text("Wyspa nie pojawi się, gdy aktywna jest wybrana aplikacja.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if settings.hiddenAppBundleIDs.isEmpty {
                        Text("Brak wybranych aplikacji.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(settings.hiddenAppBundleIDs, id: \.self) { bundleID in
                            HiddenAppRow(bundleID: bundleID) {
                                removeHiddenApp(bundleID)
                            }
                        }
                    }

                    Button("Dodaj aplikację…") {
                        pickApplication()
                    }
                } else {
                    Text("Ukrywanie wyspy dla wybranych aplikacji jest funkcją Premium — aktywuj licencję w sekcji poniżej.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Premium") {
                if LicenseMode.current.isEnforced {
                    Text("Lustro kamery, motywy, większy schowek i inne funkcje wymagają aktywacji licencji.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Okres beta — wszystkie funkcje Premium są odblokowane bez klucza.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Wprowadź klucz licencji…", action: onOpenLicense)
            }
        }
        .padding()
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
        panel.prompt = "Dodaj"
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
            .help("Usuń z listy")
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
