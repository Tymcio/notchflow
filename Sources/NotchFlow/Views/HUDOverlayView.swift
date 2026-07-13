import SwiftUI

struct HUDOverlayView: View {
    let state: HUDOverlayState

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: state.kind == .volume ? "speaker.wave.2.fill" : "sun.max.fill")
                .font(.title3)
            Text(state.label)
                .font(.caption.weight(.semibold))
            ProgressView(value: state.value)
                .progressViewStyle(.linear)
                .frame(width: 120)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: IslandRadius.large, style: .continuous))
    }
}
