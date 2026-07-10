import SwiftUI

struct IdleMediaView: View {
    let state: MediaPlaybackState
    let wingWidth: CGFloat
    let notchCutoutWidth: CGFloat
    let innerOverlap: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            idleWing(isLeading: true) {
                ArtworkView(
                    artworkURL: state.artworkURL,
                    artworkData: state.artworkData,
                    trackKey: state.trackKey,
                    size: min(wingWidth - 12, 22)
                )
            }
            .frame(width: wingWidth + innerOverlap)

            Color.clear
                .frame(width: max(0, notchCutoutWidth - innerOverlap * 2))
                .allowsHitTesting(false)

            idleWing(isLeading: false) {
                EqualizerView(isAnimating: true, seed: state.title.hashValue, barColor: .white)
            }
            .frame(width: wingWidth + innerOverlap)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
