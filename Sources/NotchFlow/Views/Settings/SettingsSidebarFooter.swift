import SwiftUI

struct SettingsSidebarFooter: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            #if canImport(Sparkle)
            if SparkleUpdaterController.shared.isConfigured {
                Button(loc("Check for updates")) {
                    SparkleUpdaterController.shared.checkForUpdates()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            } else {
                LocText("Updates disabled in local build.")
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
