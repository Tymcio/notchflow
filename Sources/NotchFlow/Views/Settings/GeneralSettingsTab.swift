import SwiftUI

struct GeneralSettingsTab: View {
    @Bindable var settings: NotchSettings
    @ObservedObject var menuBarLayoutManager: MenuBarLayoutManager
    var onOpenLicense: () -> Void

    var body: some View {
        Form {
            Toggle("Uruchamiaj przy logowaniu", isOn: $settings.launchAtLogin)
                .onChange(of: settings.launchAtLogin) { _, enabled in
                    enabled ? LaunchAtLoginService.enable() : LaunchAtLoginService.disable()
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
