import SwiftUI

struct AppearanceSettingsTab: View {
    @Bindable var settings: NotchSettings
    let isPremium: Bool

    var body: some View {
        Form {
            Picker("Motyw", selection: $settings.selectedTheme) {
                ForEach(IslandTheme.allCases) { theme in
                    Text(theme.title).tag(theme)
                }
            }
            .disabled(!isPremium && settings.selectedTheme != .system)

            if isPremium {
                HStack {
                    Text("Szerokość wyspy")
                    Slider(value: $settings.customIslandWidth, in: 280...420)
                }
                HStack {
                    Text("Wysokość schowka")
                    Slider(
                        value: $settings.customIslandHeight,
                        in: NotchFlowConstants.minimumExpandedContentHeight...NotchFlowConstants.maximumExpandedContentHeight
                    )
                }
                Text("Kalendarz i pozostałe zakładki dopasowują wysokość do treści automatycznie.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Premium odblokowuje własny rozmiar wyspy i motywy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
