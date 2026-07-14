import SwiftUI

struct SettingsSidebarFooter: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            #if canImport(Sparkle)
            if SparkleUpdaterController.shared.isConfigured {
                Button("Sprawdź aktualizacje") {
                    SparkleUpdaterController.shared.checkForUpdates()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            } else {
                Text("Aktualizacje wyłączone w lokalnym buildzie.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            #endif

            Text(AppVersionInfo.displayString)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
