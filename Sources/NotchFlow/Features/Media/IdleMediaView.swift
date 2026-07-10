import SwiftUI

struct IdleMediaView: View {
    let state: MediaPlaybackState
    let leftWingWidth: CGFloat
    let rightWingWidth: CGFloat
    let notchCutoutWidth: CGFloat
    let innerOverlap: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            if leftWingWidth > 0 {
                idleWing(isLeading: true) {
                    ArtworkView(
                        artworkURL: state.artworkURL,
                        artworkData: state.artworkData,
                        trackKey: state.trackKey,
                        size: min(leftWingWidth - 12, 22)
                    )
                }
                .frame(width: leftWingWidth + innerOverlap)
            }

            Color.clear
                .frame(width: centerClearWidth)
                .allowsHitTesting(false)

            if rightWingWidth > 0 {
                idleWing(isLeading: false) {
                    EqualizerView(isAnimating: state.isPlaying, seed: state.title.hashValue, barColor: .white)
                }
                .frame(width: rightWingWidth + innerOverlap)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var centerClearWidth: CGFloat {
        let leftOverlap = leftWingWidth > 0 ? innerOverlap : 0
        let rightOverlap = rightWingWidth > 0 ? innerOverlap : 0
        return max(0, notchCutoutWidth - leftOverlap - rightOverlap)
    }

    @ViewBuilder
    private func idleWing<Content: View>(isLeading: Bool, @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                NotchWingShape(isLeading: isLeading)
                    .fill(.black)
            }
    }
}
