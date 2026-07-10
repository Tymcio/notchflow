import SwiftUI

struct PrivacySettingsTab: View {
    @Bindable var settings: NotchSettings

    var body: some View {
        Form {
            Toggle("Monitoruj schowek", isOn: $settings.clipboardMonitoringEnabled)
                .onChange(of: settings.clipboardMonitoringEnabled) { _, enabled in
                    AppController.appState?.setClipboardMonitoringEnabled(enabled)
                }
            Text("Zapisuje lokalnie ostatnie skopiowane teksty i linki. Hasła i ukryte wpisy ze schowka są pomijane. Domyślnie wyłączone.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Zezwól na automatyzację URL scheme (notchflow://)", isOn: $settings.urlSchemeAutomationEnabled)
            Text("Gdy wyłączone, inne aplikacje nie mogą sterować NotchFlow przez adres notchflow://. Lustro kamery wymaga dodatkowego potwierdzenia.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Udostępniaj tytuły utworów do wyszukiwania tekstów", isOn: $settings.lyricsSharingEnabled)
            Text("Wysyła tytuł i artystę do lrclib.net wyłącznie podczas odtwarzania i tylko gdy włączone.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("NotchFlow nie zbiera telemetrii w wersji 1.0.")
            Text("Dostęp do sieci służy weryfikacji licencji, aktualizacjom i opcjonalnemu API lokalnemu.")
            Link("Polityka bezpieczeństwa i prywatności", destination: NotchFlowConstants.websiteURL.appending(path: "security"))
        }
        .padding()
    }
}
