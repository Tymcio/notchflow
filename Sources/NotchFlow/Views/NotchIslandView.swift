import SwiftUI

struct NotchIslandView: View {
    let isExpanded: Bool
    let geometry: NotchGeometry?
    @Bindable var appState: AppState

    @State private var isDropTargeted = false

    private let islandFill = NotchFlowBrand.spaceBlack

    var body: some View {
        ZStack(alignment: .top) {
            islandBody
            if let hud = appState.hudState {
                HUDOverlayView(state: hud)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: isExpanded)
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

    @ViewBuilder
    private func idleIsland(geometry: NotchGeometry, activity: LiveActivityKind) -> some View {
        IdleLiveActivityView(
            activity: activity,
            mediaState: appState.mediaState,
            accent: appState.settings.selectedTheme.accent,
            leftWingWidth: geometry.idleLeftWingWidth,
            rightWingWidth: geometry.idleRightWingWidth,
            notchCutoutWidth: geometry.physicalNotchCutoutWidth,
            innerOverlap: NotchFlowConstants.idleWingInnerOverlap,
            onAnswerCall: { appState.answerIncomingCall() },
            onDeclineCall: { appState.declineIncomingCall() }
        )
        .frame(width: geometry.idleSize.width, height: geometry.idleSize.height)
    }

    @ViewBuilder
    private func expandedIsland(geometry: NotchGeometry) -> some View {
        let shape = ExpandedNotchShape(topCornerRadius: 12, bottomCornerRadius: 20)

        VStack(spacing: 8) {
            if geometry.hasPhysicalNotch {
                ExpandedNotchTabBar(
                    activeModule: $appState.activeModule,
                    isPremium: appState.isPremium,
                    notchCutoutWidth: geometry.physicalNotchCutoutWidth,
                    badgeCounts: tabBadgeCounts
                )
            } else {
                IslandTabBar(
                    activeModule: $appState.activeModule,
                    isPremium: appState.isPremium,
                    badgeCounts: tabBadgeCounts
                )
            }

            moduleContent
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .padding(.top, geometry.hasPhysicalNotch ? expandedContentTopInset(geometry) : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .animation(nil, value: appState.activeModule)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background { shape.fill(islandFill) }
        .clipShape(shape)
        .overlay { shape.stroke(.white.opacity(0.08), lineWidth: 0.5) }
        .overlay {
            if isDropTargeted || appState.displayManager.isDragNearNotch {
                shape.stroke(appState.settings.selectedTheme.accent, lineWidth: 1.5)
            }
        }
        .overlay(alignment: .bottom) {
            if appState.displayManager.isDragNearNotch && !isDropTargeted {
                Text("Upuść na półkę")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(appState.settings.selectedTheme.accent)
                    .padding(.bottom, 10)
            }
        }
        .onDrop(of: [.fileURL, .url], isTargeted: $isDropTargeted) { providers in
            Task {
                await appState.shelfManager.handleDrop(providers: providers, isPremium: appState.isPremium)
                await MainActor.run {
                    appState.activeModule = .shelf
                }
            }
            return true
        }
    }

    private var tabBadgeCounts: [IslandModule: Int] {
        var counts: [IslandModule: Int] = [:]
        if appState.shelfBadgeCount > 0 {
            counts[.shelf] = appState.shelfBadgeCount
        }
        return counts
    }

    private func expandedContentTopInset(_ geometry: NotchGeometry) -> CGFloat {
        max(0, geometry.notchTopInset - 22)
    }

    @ViewBuilder
    private var moduleContent: some View {
        switch appState.activeModule {
        case .media:
            MediaPlayerView(
                state: appState.mediaState,
                onPlayPause: { appState.mediaMonitor.togglePlayPause() },
                onNext: { appState.mediaMonitor.nextTrack() },
                onPrevious: { appState.mediaMonitor.previousTrack() },
                onSeek: { appState.mediaMonitor.seek(to: $0) }
            )
        case .calendar:
            CalendarTabView()
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
