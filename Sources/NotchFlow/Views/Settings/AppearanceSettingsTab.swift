import SwiftUI

struct AppearanceSettingsTab: View {
    @Bindable var settings: NotchSettings
    let isPremium: Bool

    var body: some View {
        SettingsFormContent {
            Section {
                Picker(loc("Theme"), selection: $settings.selectedTheme) {
                    ForEach(IslandTheme.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                .disabled(!isPremium && settings.selectedTheme != .system)
            }

            Section {
                if isPremium {
                    LabeledContent(loc("Island width")) {
                        Slider(value: $settings.customIslandWidth, in: 280...420)
                            .frame(maxWidth: 220)
                    }
                    LabeledContent(loc("Clipboard height")) {
                        Slider(
                            value: $settings.customIslandHeight,
                            in: NotchFlowConstants.minimumExpandedContentHeight...NotchFlowConstants.maximumExpandedContentHeight
                        )
                        .frame(maxWidth: 220)
                    }
                }
            } header: {
                Text(loc("Island size"))
            } footer: {
                if isPremium {
                    SettingsFooterCaption("Calendar and other tabs adjust height to content automatically.")
                } else {
                    SettingsFooterCaption("Premium unlocks custom island size and themes.")
                }
            }
        }
    }
}
