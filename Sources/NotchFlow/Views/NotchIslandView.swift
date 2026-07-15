import SwiftUI

@MainActor
struct NotchIslandView: View {
    let isExpanded: Bool
    @ObservedObject var displayManager: DisplayManager
    @Bindable var appState: AppState

    private let islandFill = NotchFlowBrand.spaceBlack

    private var geometry: NotchGeometry? {
        displayManager.geometry
    }

    private var effectiveExpandedHeight: CGFloat? {
        // Always follow the geometry height: the panel window is sized from it, and any
        // taller frame here makes NSHostingView grow the window upward past the screen top.
        // Geometry already starts from the module's estimate before intrinsic measurement.
        guard isExpanded, let geometry else { return nil }
        return geometry.expandedSize.height
    }

    private var showsFileDropChrome: Bool {
        displayManager.isFileDragInProgress && displayManager.isDragNearNotch
    }

    var body: some View {
        ZStack {
            islandBody
            if let hud = appState.hudState {
                HUDOverlayView(state: hud)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .frame(
            width: isExpanded ? geometry?.expandedSize.width : idlePanelWidth,
            height: isExpanded ? effectiveExpandedHeight : geometry?.idleSize.height,
            alignment: .topLeading
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var islandBody: some View {
        if let geometry {
            if isExpanded {
                expandedIsland(geometry: geometry)
            } else if let activity = appState.activeLiveActivity {
                idleIsland(geometry: geometry, activity: activity)
            }
        }
    }

    private var idlePanelWidth: CGFloat? {
        guard let geometry else { return nil }
        return geometry.idleWingLayout(rightWingWidth: appState.idleRightWingWidthOverride).panelWidth
    }

    @ViewBuilder
    private func idleIsland(geometry: NotchGeometry, activity: LiveActivityKind) -> some View {
        let wingLayout = geometry.idleWingLayout(rightWingWidth: appState.idleRightWingWidthOverride)
        IdleLiveActivityView(
            activity: activity,
            mediaState: appState.mediaState,
            accent: appState.settings.selectedTheme.accent,
            wingLayout: wingLayout,
            onAnswerCall: { appState.answerIncomingCall() },
            onDeclineCall: { appState.declineIncomingCall() }
        )
        .frame(width: wingLayout.panelWidth, height: wingLayout.panelHeight, alignment: .topLeading)
        .clipShape(Rectangle())
    }

    @ViewBuilder
    private func expandedIsland(geometry: NotchGeometry) -> some View {
        let shape = ExpandedNotchShape(topCornerRadius: 12, bottomCornerRadius: 20)
        let panelWidth = geometry.expandedSize.width
        let usesIntrinsicHeight = appState.activeModule.prefersIntrinsicExpandedHeight

        Group {
            if usesIntrinsicHeight {
                expandedContentStack(panelWidth: panelWidth)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: panelWidth, alignment: .top)
                    .reportExpandedIslandStackHeight()
            } else {
                expandedContentStack(panelWidth: panelWidth)
                    .frame(width: panelWidth, height: geometry.expandedSize.height, alignment: .top)
            }
        }
        .background {
            shape.fill(islandFill)
        }
        .clipShape(shape)
        .overlay {
            shape.stroke(IslandStyle.surfaceStroke, lineWidth: 0.5)
        }
        .overlay {
            if showsFileDropChrome {
                shape.stroke(appState.settings.selectedTheme.accent, lineWidth: 1.5)
            }
        }
        .overlay(alignment: .bottom) {
            if showsFileDropChrome {
                LocText("Drop onto shelf")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(appState.settings.selectedTheme.accent)
                    .padding(.bottom, 10)
            }
        }
        .onPreferenceChange(ExpandedIslandStackHeightKey.self) { stackHeight in
            guard appState.activeModule.prefersIntrinsicExpandedHeight, stackHeight > 0 else { return }
            displayManager.applyIntrinsicExpandedHeight(
                stackHeight.rounded(.up),
                for: appState.activeModule
            )
        }
        .onChange(of: appState.activeModule) { _, module in
            if module != .mirror {
                appState.cameraMirrorManager.stopPreview()
            }
            displayManager.clearDragDropState()
            displayManager.updateExpandedHeight(for: module)
            AppController.panelController?.syncMediaPollingState()
        }
        .animation(IslandMotion.quick, value: appState.activeModule)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard displayManager.isFileDragInProgress else { return false }
            Task {
                await appState.shelfManager.handleDrop(providers: providers, isPremium: appState.isPremium)
                await MainActor.run {
                    appState.activeModule = .shelf
                }
            }
            return true
        }
    }

    @ViewBuilder
    private func expandedContentStack(panelWidth: CGFloat) -> some View {
        VStack(spacing: NotchFlowConstants.expandedTabToContentSpacing) {
            if geometry?.hasPhysicalNotch == true {
                ExpandedNotchTabBar(
                    activeModule: $appState.activeModule,
                    isPremium: appState.isPremium,
                    notchCutoutWidth: geometry?.physicalNotchCutoutWidth ?? 0,
                    badgeCounts: tabBadgeCounts
                )
                .frame(height: NotchFlowConstants.expandedTabBarHeight, alignment: .top)
            } else {
                IslandTabBar(
                    activeModule: $appState.activeModule,
                    isPremium: appState.isPremium,
                    badgeCounts: tabBadgeCounts
                )
                .frame(height: NotchFlowConstants.expandedTabBarHeight, alignment: .top)
            }

            moduleContent(in: geometry)
                .padding(.horizontal, 16)
                .padding(.bottom, NotchFlowConstants.expandedContentBottomPadding)
                .frame(maxWidth: .infinity, alignment: .top)
                .id(appState.activeModule)
                .transition(.opacity)
        }
        .frame(width: panelWidth, alignment: .top)
    }

    private var tabBadgeCounts: [IslandModule: Int] {
        var counts: [IslandModule: Int] = [:]
        if appState.shelfBadgeCount > 0 {
            counts[.shelf] = appState.shelfBadgeCount
        }
        return counts
    }

    private func expandedModuleContentHeight(_ geometry: NotchGeometry?) -> CGFloat {
        let contentCap = appState.isPremium
            ? appState.settings.customIslandHeight
            : NotchFlowConstants.maximumExpandedContentHeight
        let panelHeight = geometry?.expandedSize.height
            ?? NotchFlowConstants.expandedTotalHeight(forContentHeight: contentCap)
        let chrome = NotchFlowConstants.expandedTabBarHeight
            + NotchFlowConstants.expandedTabToContentSpacing
            + NotchFlowConstants.expandedContentBottomPadding
        return max(
            min(contentCap, panelHeight - chrome),
            NotchFlowConstants.minimumExpandedContentHeight
        )
    }

    @ViewBuilder
    private func moduleContent(in geometry: NotchGeometry?) -> some View {
        let content = moduleContent
        if appState.activeModule.prefersIntrinsicExpandedHeight {
            content
        } else {
            content
                .frame(
                    height: expandedModuleContentHeight(geometry),
                    alignment: .top
                )
        }
    }

    @ViewBuilder
    private var moduleContent: some View {
        switch appState.activeModule {
        case .media:
            MediaPlayerView(
                state: appState.mediaState,
                showsLyrics: appState.isPremium,
                onPlayPause: { appState.mediaMonitor.togglePlayPause() },
                onNext: { appState.mediaMonitor.nextTrack() },
                onPrevious: { appState.mediaMonitor.previousTrack() },
                onSeek: { appState.mediaMonitor.seek(to: $0) }
            )
        case .calendar:
            CalendarTabView(appState: appState)
        case .shelf:
            ShelfTabView(appState: appState)
        case .focus:
            FocusTabView(appState: appState)
        case .notes:
            QuickNotesView(appState: appState)
        case .clipboard:
            ClipboardHistoryView(appState: appState)
        case .mirror:
            CameraMirrorView(appState: appState)
        }
    }
}
