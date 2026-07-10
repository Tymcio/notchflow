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
                    Text("Wysokość wyspy")
                    Slider(value: $settings.customIslandHeight, in: 120...200)
                }
            } else {
                Text("Premium odblokowuje własny rozmiar wyspy i motywy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
