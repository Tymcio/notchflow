import SwiftUI

struct IdleMediaView: View {
    let state: MediaPlaybackState
    let wingLayout: IdleWingLayout

    var body: some View {
        IdleWingRow(
            layout: wingLayout,
            showsLeftWing: wingLayout.visibleLeftWidth > 0,
            showsRightWing: wingLayout.visibleRightWidth > 0,
            leading: {
                ArtworkView(
                    artworkURL: state.artworkURL,
                    artworkData: state.artworkData,
                    trackKey: state.trackKey,
                    size: min(wingLayout.visibleLeftWidth - 12, 22)
                )
            },
            trailing: {
                EqualizerView(isAnimating: state.isPlaying, seed: state.title.hashValue, barColor: .white)
            }
        )
    }
}
