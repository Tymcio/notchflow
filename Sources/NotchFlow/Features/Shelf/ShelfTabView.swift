import AppKit
import SwiftUI

@MainActor
struct ShelfTabView: View {
    @Bindable var appState: AppState

    private let trackHeight: CGFloat = 72
    private let tileWidth: CGFloat = 68

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

    private var isDropActive: Bool {
        appState.displayManager.isFileDragInProgress && appState.displayManager.isDragNearNotch
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            shelfToolbar
                .padding(.bottom, 10)

            shelfTrack

            shelfFooter
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            Task {
                await appState.shelfManager.handleDrop(providers: providers, isPremium: appState.isPremium)
            }
            return true
        }
    }

    private var shelfToolbar: some View {
        HStack(spacing: 10) {
            Label {
                LocText("Shelf")
                    .font(.caption.weight(.semibold))
            } icon: {
                Image(systemName: "tray.full.fill")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(IslandStyle.primaryText)

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                quotaCapsule(
                    icon: "pin.fill",
                    label: loc("Pinned"),
                    count: pinned.count,
                    limit: pinnedLimit,
                    tint: accent
                )
                quotaCapsule(
                    icon: "clock.arrow.circlepath",
                    label: loc("Temporary"),
                    count: dropped.count,
                    limit: droppedLimit,
                    tint: IslandStyle.secondaryText
                )
            }
        }
    }

    @ViewBuilder
    private func quotaCapsule(icon: String, label: String, count: Int, limit: Int, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(tint)

            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(IslandStyle.secondaryText)

            Text("\(count)/\(limit)")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(count >= limit ? Color.orange.opacity(0.9) : IslandStyle.tertiaryText)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.07), lineWidth: 0.5)
                }
        }
    }

    private var shelfTrack: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(pinned) { item in
                    shelfCard(item, style: .pinned, allowsPin: false)
                }

                if pinned.count < pinnedLimit {
                    addPinnedTile
                }

                if !pinned.isEmpty || !dropped.isEmpty {
                    sectionDivider
                }

                if dropped.isEmpty {
                    dropPlaceholder
                } else {
                    ForEach(dropped) { item in
                        shelfCard(item, style: .temporary, allowsPin: true)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(height: trackHeight)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.045),
                            Color.white.opacity(0.02)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            isDropActive ? accent.opacity(0.55) : Color.white.opacity(0.08),
                            lineWidth: isDropActive ? 1 : 0.5
                        )
                }
        }
        .animation(.easeOut(duration: 0.2), value: isDropActive)
    }

    private var sectionDivider: some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0), Color.white.opacity(0.14), Color.white.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 1, height: 48)
            .padding(.horizontal, 4)
    }

    private var addPinnedTile: some View {
        Button(action: pickPinnedFile) {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.12))
                        .frame(width: 34, height: 34)
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accent)
                }
                LocText("Add")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(IslandStyle.secondaryText)
            }
            .frame(width: tileWidth, height: trackHeight - 12)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.03))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(accent.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    }
            }
        }
        .buttonStyle(.plain)
        .help(loc("Add pinned file shortcut"))
    }

    private var dropPlaceholder: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(isDropActive ? accent.opacity(0.18) : Color.white.opacity(0.06))
                    .frame(width: 32, height: 32)
                Image(systemName: isDropActive ? "arrow.down.circle.fill" : "arrow.down.doc")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isDropActive ? accent : IslandStyle.tertiaryText)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(isDropActive ? loc("Drop here") : loc("Temporary files"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isDropActive ? accent : IslandStyle.secondaryText)
                LocText("Drag onto the island")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(IslandStyle.tertiaryText)
            }
        }
        .padding(.horizontal, 12)
        .frame(minWidth: 148)
        .frame(height: trackHeight - 12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isDropActive ? accent.opacity(0.08) : Color.white.opacity(0.02))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            isDropActive ? accent.opacity(0.45) : Color.white.opacity(0.08),
                            style: StrokeStyle(lineWidth: 1, dash: [6, 5])
                        )
                }
        }
        .animation(.easeOut(duration: 0.2), value: isDropActive)
    }

    @ViewBuilder
    private var shelfFooter: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "hand.point.up.left.fill")
                    .font(.system(size: 8))
                LocText("Click to open · right-click to pin or remove")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(IslandStyle.tertiaryText)
            .frame(maxWidth: .infinity, alignment: .center)

            if !appState.isPremium {
                Text(locFormat("Free: %lld pinned, %lld temporary", NotchFlowConstants.freePinnedShelfLimit, NotchFlowConstants.freeDroppedShelfLimit))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(IslandStyle.tertiaryText.opacity(0.85))
            }
        }
    }

    @ViewBuilder
    private func shelfCard(_ item: ShelfItem, style: ShelfCardStyle, allowsPin: Bool) -> some View {
        ShelfItemCard(
            item: item,
            accent: accent,
            style: style,
            tileWidth: tileWidth,
            resolveURL: { appState.shelfManager.resolvePinnedURL(for: item) ?? item.resolvedURL },
            onOpen: { appState.shelfManager.open(item) },
            onReveal: { appState.shelfManager.revealInFinder(item) },
            onPin: allowsPin ? {
                appState.shelfManager.pinDroppedItem(item, isPremium: appState.isPremium)
            } : nil,
            onRemove: { appState.shelfManager.remove(item) }
        )
    }

    private func pickPinnedFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = loc("Pin")
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        if appState.shelfManager.pinURL(url, isPremium: appState.isPremium) != nil {
            appState.activeModule = .shelf
        }
    }
}

private enum ShelfCardStyle {
    case pinned
    case temporary
}

private struct ShelfItemCard: View {
    let item: ShelfItem
    let accent: Color
    let style: ShelfCardStyle
    let tileWidth: CGFloat
    let resolveURL: () -> URL
    var onOpen: () -> Void
    var onReveal: () -> Void
    var onPin: (() -> Void)?
    var onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        let url = resolveURL()

        Button(action: onOpen) {
            VStack(spacing: 5) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 34, height: 34)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .onDrag {
                        NSItemProvider(object: url as NSURL)
                    }

                Text(item.displayName)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(isHovered ? IslandStyle.primaryText : IslandStyle.secondaryText)
                    .frame(maxWidth: tileWidth - 8)
            }
            .frame(width: tileWidth, height: 60)
            .background { tileBackground }
            .overlay(alignment: .top) {
                if style == .pinned {
                    Capsule(style: .continuous)
                        .fill(accent.opacity(isHovered ? 0.9 : 0.55))
                        .frame(width: 18, height: 2)
                        .padding(.top, 4)
                }
            }
            .scaleEffect(isHovered ? 1.04 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button(loc("Open"), action: onOpen)
            Button(loc("Reveal in Finder"), action: onReveal)
            if let onPin {
                Button(loc("Pin permanently"), action: onPin)
            }
            Divider()
            Button(loc("Remove"), role: .destructive, action: onRemove)
        }
        .help(item.displayName)
    }

    @ViewBuilder
    private var tileBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(
                isHovered
                    ? Color.white.opacity(0.1)
                    : Color.white.opacity(style == .pinned ? 0.06 : 0.04)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        style == .pinned
                            ? accent.opacity(isHovered ? 0.35 : 0.15)
                            : Color.white.opacity(isHovered ? 0.16 : 0.07),
                        lineWidth: 0.5
                    )
            }
    }
}
