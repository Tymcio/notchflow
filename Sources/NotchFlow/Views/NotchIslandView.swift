import SwiftUI

struct NotchIslandView: View {
    let isExpanded: Bool
    let geometry: NotchGeometry?
    @Bindable var appState: AppState

    @State private var isDropTargeted = false

    private let islandFill = Color(red: 0.08, green: 0.08, blue: 0.09)

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
            } else if appState.shouldShowIdleNotch {
                idleIsland(geometry: geometry)
            }
        }
    }

    @ViewBuilder
    private func idleIsland(geometry: NotchGeometry) -> some View {
        IdleMediaView(
            state: appState.mediaState,
            wingWidth: geometry.idleWingWidth,
            notchCutoutWidth: geometry.physicalNotchCutoutWidth,
            innerOverlap: NotchFlowConstants.idleWingInnerOverlap
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
                    isPremium: appState.isPremium
                )
            } else {
                IslandTabBar(
                    activeModule: $appState.activeModule,
                    isPremium: appState.isPremium
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
            if isDropTargeted {
                shape.stroke(appState.settings.selectedTheme.accent, lineWidth: 1.5)
            }
        }
        .onDrop(of: [.fileURL, .url], isTargeted: $isDropTargeted) { providers in
            Task {
                await appState.shelfManager.handleDrop(providers: providers, isPremium: appState.isPremium)
            }
            return true
        }
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
                isPremium: appState.isPremium,
                onPlayPause: { appState.mediaMonitor.togglePlayPause() },
                onNext: { appState.mediaMonitor.nextTrack() },
                onPrevious: { appState.mediaMonitor.previousTrack() },
                onSeek: { appState.mediaMonitor.seek(to: $0) }
            )
        case .calendar:
            CalendarTabView()
        case .notes:
            QuickNotesView(appState: appState)
        case .clipboard:
            ClipboardHistoryView(appState: appState)
        case .mirror:
            CameraMirrorView(appState: appState)
        }
    }
}

struct IslandClipShape: Shape {
    let hasPhysicalNotch: Bool
    let isExpanded: Bool

    func path(in rect: CGRect) -> Path {
        NotchShape(hasPhysicalNotch: hasPhysicalNotch, isExpanded: isExpanded).path(in: rect)
    }
}
