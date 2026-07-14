import SwiftUI

/// Shared grouped-form styling for settings detail panes.
struct SettingsFormContent<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        Form(content: content)
            .formStyle(.grouped)
            .scrollContentBackground(.visible)
    }
}

/// Secondary caption text for section footers and helper rows.
struct SettingsFooterCaption: View {
    private let text: Text

    init(_ key: String) {
        text = Text(loc(key))
    }

    var body: some View {
        text
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
