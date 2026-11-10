import SwiftUI

/// The volume / brightness level over the expanded island: the same symbol and bar as the
/// idle wings, in a small capsule.
struct HUDOverlayView: View {
    let state: HUDOverlayState
    let accent: Color

    var body: some View {
        HStack(spacing: 10) {
            HUDSymbolImage(hud: state, size: 13)
            HUDLevelBar(level: state.displayLevel, accent: accent)
                .frame(width: 110, height: IdleHUDMetrics.barHeight)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(IslandStyle.islandFill, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous).stroke(IslandStyle.surfaceStroke, lineWidth: 0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.accessibilityLabel)
        .accessibilityValue(state.accessibilityValue)
        .allowsHitTesting(false)
    }
}
