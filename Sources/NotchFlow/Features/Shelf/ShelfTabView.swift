import AppKit
import SwiftUI

struct ShelfTabView: View {
    @Bindable var appState: AppState

    private var accent: Color {
        appState.settings.selectedTheme.accent
    }

    private var pinned: [ShelfItem] {
        appState.shelfItems.filter { $0.kind == .pinned }
    }

    private var dropped: [ShelfItem] {
        appState.shelfItems.filter { $0.kind == .dropped }
    }

    private var pinnedLimit: Int {
        appState.isPremium ? NotchFlowConstants.premiumPinnedShelfLimit : NotchFlowConstants.freePinnedShelfLimit
    }

    private var droppedLimit: Int {
        appState.isPremium ? NotchFlowConstants.premiumDroppedShelfLimit : NotchFlowConstants.freeDroppedShelfLimit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            pinnedLane
            temporaryLane

            if !appState.isPremium {
                Text("\(pinned.count)/\(NotchFlowConstants.freePinnedShelfLimit) przypiętych · \(dropped.count)/\(NotchFlowConstants.freeDroppedShelfLimit) tymczasowych")
                    .font(.caption2)
                    .foregroundStyle(IslandStyle.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: appState.shelfItems.map(\.id))
    }

    // MARK: - Lanes

    private var pinnedLane: some View {
        VStack(alignment: .leading, spacing: 8) {
            laneHeader(
                icon: "pin.fill",
                title: "Przypięte",
                count: pinned.count,
                limit: pinnedLimit,
                tint: accent
            ) {
                pickPinnedFile()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(pinned) { item in
                        ShelfItemCard(
                            item: item,
                            accent: accent,
                            style: .pinned,
                            resolveURL: { appState.shelfManager.resolvePinnedURL(for: item) ?? item.resolvedURL },
                            onOpen: { appState.shelfManager.open(item) },
                            onReveal: { appState.shelfManager.revealInFinder(item) },
                            onRemove: { appState.shelfManager.remove(item) }
                        )
                        .transition(.scale(scale: 0.88).combined(with: .opacity))
                    }

                    addPinnedSlot
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
            .frame(height: 86)
        }
    }

    private var temporaryLane: some View {
        VStack(alignment: .leading, spacing: 8) {
            laneHeader(
                icon: "tray.and.arrow.down.fill",
                title: "Tymczasowe",
                count: dropped.count,
                limit: droppedLimit,
                tint: .white.opacity(0.7),
                onAdd: nil
            )

            if dropped.isEmpty {
                dropHintStrip
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(dropped) { item in
                            ShelfItemCard(
                                item: item,
                                accent: accent,
                                style: .temporary,
                                resolveURL: { appState.shelfManager.resolvePinnedURL(for: item) ?? item.resolvedURL },
                                onOpen: { appState.shelfManager.open(item) },
                                onReveal: { appState.shelfManager.revealInFinder(item) },
                                onPin: {
                                    appState.shelfManager.pinDroppedItem(item, isPremium: appState.isPremium)
                                },
                                onRemove: { appState.shelfManager.remove(item) }
                            )
                            .transition(.scale(scale: 0.88).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 2)
                }
                .frame(height: 86)
            }
        }
    }

    // MARK: - Components

    @ViewBuilder
    private func laneHeader(
        icon: String,
        title: String,
        count: Int,
        limit: Int,
        tint: Color,
        onAdd: (() -> Void)?
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(IslandStyle.accentText)

            Text("\(count)/\(limit)")
                .font(.caption2.weight(.medium))
                .foregroundStyle(IslandStyle.tertiaryText)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(0.06)))

            Spacer()

            if let onAdd {
                Button(action: onAdd) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(accent.opacity(0.9))
                }
                .buttonStyle(.plain)
                .help("Dodaj przypięty skrót")
            }
        }
    }

    private var addPinnedSlot: some View {
        Button(action: pickPinnedFile) {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(accent.opacity(0.85))
                Text("Dodaj")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(IslandStyle.secondaryText)
            }
            .frame(width: 72, height: 72)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(accent.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(accent.opacity(0.06))
                    }
            }
        }
        .buttonStyle(.plain)
    }

    private var dropHintStrip: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.doc.fill")
                .font(.title3)
                .foregroundStyle(accent.opacity(0.55))
            VStack(alignment: .leading, spacing: 2) {
                Text("Upuść pliki na wyspę")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(IslandStyle.primaryText)
                Text("Pojawią się tutaj — przeciągnij stąd gdzie chcesz")
                    .font(.caption2)
                    .foregroundStyle(IslandStyle.secondaryText)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.03))
                }
        }
    }

    private func pickPinnedFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Przypnij"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if appState.shelfManager.pinURL(url, isPremium: appState.isPremium) != nil {
            appState.activeModule = .shelf
        }
    }
}

// MARK: - Item card

private enum ShelfCardStyle {
    case pinned
    case temporary
}

private struct ShelfItemCard: View {
    let item: ShelfItem
    let accent: Color
    let style: ShelfCardStyle
    let resolveURL: () -> URL
    var onOpen: () -> Void
    var onReveal: () -> Void
    var onPin: (() -> Void)?
    var onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        let url = resolveURL()
        let parentName = url.deletingLastPathComponent().lastPathComponent

        VStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 36, height: 36)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 2)

                if style == .pinned {
                    Circle()
                        .fill(accent)
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 0.5))
                        .offset(x: 3, y: -3)
                }
            }

            Text(item.displayName)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(IslandStyle.primaryText)

            Text(parentName)
                .font(.system(size: 9))
                .lineLimit(1)
                .foregroundStyle(IslandStyle.tertiaryText)
        }
        .frame(width: 76, height: 72)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    isHovered
                        ? Color.white.opacity(0.11)
                        : Color.white.opacity(0.06)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            style == .pinned ? accent.opacity(isHovered ? 0.45 : 0.22) : Color.white.opacity(0.08),
                            lineWidth: 0.5
                        )
                }
        }
        .scaleEffect(isHovered ? 1.04 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isHovered)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Otwórz", action: onOpen)
            Button("Pokaż w Finderze", action: onReveal)
            if let onPin {
                Button("Przypnij", action: onPin)
            }
            Divider()
            Button("Usuń", role: .destructive, action: onRemove)
        }
        .onDrag {
            NSItemProvider(object: url as NSURL)
        }
        .help(item.displayName)
    }
}
