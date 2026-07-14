import AppKit
import SwiftUI

@MainActor
struct ClipboardHistoryView: View {
    @Bindable var appState: AppState
    @State private var query = ""
    @State private var apiBaseURL = ""
    @State private var copiedAPIInfo = false
    @FocusState private var isSearchFocused: Bool

    private var monitoringEnabled: Bool {
        appState.settings.clipboardMonitoringEnabled
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                if !monitoringEnabled {
                    disabledState
                } else {
                    enabledState
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            refreshAPIInfo()
            if monitoringEnabled {
                appState.clipboardManager.captureIfChanged()
            }
        }
        .onDisappear {
            isSearchFocused = false
            appState.isIslandInputFocused = false
        }
    }

    private var disabledState: some View {
        VStack(alignment: .leading, spacing: 10) {
            LocText("Clipboard disabled")
                .font(.caption.weight(.semibold))
                .foregroundStyle(IslandStyle.primaryText)

            LocText("NotchFlow can store recent text and links locally. Data never leaves your Mac.")
                .font(.caption2)
                .foregroundStyle(IslandStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            monitoringToggleRow(title: loc("Enable clipboard monitoring"))

            Button {
                appState.setClipboardMonitoringEnabled(true)
                appState.clipboardManager.captureCurrentContents()
            } label: {
                LocText("Enable and save now")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.black.opacity(0.88))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.white)
                    }
            }
            .buttonStyle(.plain)

            raycastSection
        }
        .padding(10)
        .background(cardBackground)
    }

    private var enabledState: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                monitoringToggleRow(title: loc("Monitoring enabled"), compact: true)

                Spacer(minLength: 8)

                Button(loc("Save now")) {
                    appState.clipboardManager.captureCurrentContents()
                }
                .font(.caption2.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(IslandStyle.accentText)
            }

            if appState.isPremium {
                searchField
            } else {
                lockedSearchField
            }

            let items = filteredEntries
            if items.isEmpty {
                LocText("Copy something — it will appear here.")
                    .font(.caption2)
                    .foregroundStyle(IslandStyle.tertiaryText)
            } else {
                LazyVStack(spacing: 6) {
                    ForEach(items) { entry in
                        entryRow(entry)
                    }
                }
            }

            Text(locFormat("Limit: %lld/%lld", items.count, appState.isPremium ? NotchFlowConstants.premiumClipboardLimit : NotchFlowConstants.freeClipboardLimit))
                .font(.caption2)
                .foregroundStyle(IslandStyle.tertiaryText)

            raycastSection
        }
    }

    private func monitoringToggleRow(title: String, compact: Bool = false) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.caption.weight(compact ? .medium : .semibold))
                .foregroundStyle(IslandStyle.primaryText)
                .lineLimit(2)

            if !compact {
                Spacer(minLength: 8)
            }

            Toggle("", isOn: monitoringBinding)
                .labelsHidden()
                .accessibilityLabel(loc("Clipboard monitoring"))
                .toggleStyle(.switch)
                .tint(.white)
        }
    }

    @ViewBuilder
    private var lockedSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.caption2)
                .foregroundStyle(IslandStyle.tertiaryText)

            LocText("Search in Premium")
                .font(.caption)
                .foregroundStyle(IslandStyle.tertiaryText)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        .foregroundStyle(IslandStyle.tertiaryText.opacity(0.5))
                }
        }
    }

    @ViewBuilder
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.caption2)
                .foregroundStyle(IslandStyle.secondaryText)

            ZStack(alignment: .leading) {
                if query.isEmpty {
                    LocText("Search history…")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.48))
                        .allowsHitTesting(false)
                }

                TextField("", text: $query)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(IslandStyle.primaryText)
                    .tint(.white)
                    .focused($isSearchFocused)
                    .onChange(of: isSearchFocused) { _, focused in
                        appState.isIslandInputFocused = focused
                    }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                AppController.panelController?.prepareForTyping()
                isSearchFocused = true
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.08))
        }
    }

    private func entryRow(_ entry: ClipboardEntry) -> some View {
        Button {
            appState.clipboardManager.copyBack(entry)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon(for: entry.kind))
                    .font(.caption2)
                    .foregroundStyle(IslandStyle.secondaryText)
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.value)
                        .font(.caption)
                        .foregroundStyle(IslandStyle.primaryText)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(entry.createdAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(IslandStyle.tertiaryText)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            }
        }
        .buttonStyle(.plain)
        .help(loc("Paste again"))
    }

    private var raycastSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            LocText("Raycast (optional)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(IslandStyle.secondaryText)

            Toggle(isOn: localAPIBinding) {
                LocText("Local API for Raycast")
                    .font(.caption)
                    .foregroundStyle(IslandStyle.primaryText)
            }
            .toggleStyle(.switch)
            .tint(.white)

            if appState.settings.localAPIEnabled {
                if apiBaseURL.isEmpty {
                    LocText("Starting API…")
                        .font(.caption2)
                        .foregroundStyle(IslandStyle.tertiaryText)
                } else {
                    Text(apiBaseURL)
                        .font(.caption2.monospaced())
                        .foregroundStyle(IslandStyle.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack(spacing: 8) {
                    Button(copiedAPIInfo ? loc("Copied") : loc("Copy configuration")) {
                        copyAPIConfig()
                    }
                    .font(.caption2.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(IslandStyle.accentText)
                    .disabled(apiBaseURL.isEmpty)

                    Button(loc("More…")) {
                        appState.openIntegrationsSettings()
                    }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundStyle(IslandStyle.tertiaryText)
                }
            } else {
                LocText("Enable so the Raycast extension can read NotchFlow clipboard history.")
                    .font(.caption2)
                    .foregroundStyle(IslandStyle.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 2)
    }

    private var monitoringBinding: Binding<Bool> {
        Binding(
            get: { appState.settings.clipboardMonitoringEnabled },
            set: { appState.setClipboardMonitoringEnabled($0) }
        )
    }

    private var localAPIBinding: Binding<Bool> {
        Binding(
            get: { appState.settings.localAPIEnabled },
            set: { enabled in
                appState.settings.localAPIEnabled = enabled
                Task {
                    if enabled {
                        try? await appState.localAPIServer.start(appState: appState)
                    } else {
                        appState.localAPIServer.stop()
                    }
                    refreshAPIInfo()
                }
            }
        )
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            }
    }

    private var filteredEntries: [ClipboardEntry] {
        let base = appState.clipboardManager.visibleEntries(isPremium: appState.isPremium)
        guard !query.isEmpty else { return base }
        return base.filter { $0.value.localizedCaseInsensitiveContains(query) }
    }

    private func icon(for kind: ClipboardEntryKind) -> String {
        switch kind {
        case .text: "doc.text"
        case .url: "link"
        case .image: "photo"
        }
    }

    private func refreshAPIInfo() {
        let apiFile = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("NotchFlow/api.json")
        guard let data = try? Data(contentsOf: apiFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let baseURL = json["baseURL"] as? String else {
            apiBaseURL = ""
            return
        }
        apiBaseURL = baseURL
    }

    private func copyAPIConfig() {
        let payload = """
        {"baseURL":"\(apiBaseURL)","token":"\(APIAuth.resolvedToken())"}
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(payload, forType: .string)
        copiedAPIInfo = true
    }
}
