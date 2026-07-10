import SwiftUI

struct ClipboardHistoryView: View {
    @Bindable var appState: AppState
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !appState.settings.clipboardMonitoringEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Clipboard monitoring is off.")
                        .font(.caption)
                        .foregroundStyle(IslandStyle.secondaryText)
                    Button("Włącz w ustawieniach") {
                        appState.openSettings()
                    }
                    .controlSize(.small)
                }
            } else {
                if appState.isPremium {
                    TextField("Search clipboard…", text: $query)
                        .textFieldStyle(.roundedBorder)
                }

                let items = filteredEntries
                if items.isEmpty {
                    Text("Copy something — we'll remember it.")
                        .font(.caption)
                        .foregroundStyle(IslandStyle.tertiaryText)
                } else {
                    ForEach(items) { entry in
                        Button {
                            appState.clipboardManager.copyBack(entry)
                        } label: {
                            HStack {
                                Image(systemName: icon(for: entry.kind))
                                    .font(.caption2)
                                    .foregroundStyle(IslandStyle.secondaryText)
                                Text(entry.value)
                                    .font(.caption)
                                    .foregroundStyle(IslandStyle.primaryText)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button("Open Raycast Clipboard History") {
                    if let url = URL(string: "raycast://extensions/raycast/clipboard-history") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .font(.caption2)
                .foregroundStyle(IslandStyle.secondaryText)
            }
        }
        .onAppear {
            appState.clipboardManager.captureIfChanged()
        }
    }

    private var filteredEntries: [ClipboardEntry] {
        let base = appState.clipboardManager.visibleEntries(isPremium: appState.isPremium)
        guard appState.isPremium, !query.isEmpty else { return base }
        return base.filter { $0.value.localizedCaseInsensitiveContains(query) }
    }

    private func icon(for kind: ClipboardEntryKind) -> String {
        switch kind {
        case .text: "doc.text"
        case .url: "link"
        case .image: "photo"
        }
    }
}

import AppKit
