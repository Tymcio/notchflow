import SwiftUI

enum IdleHUDMetrics {
    static let barWidth: CGFloat = 100
    static let barHeight: CGFloat = 6
    static let barLeadingPadding: CGFloat = 6
    static let barTrailingPadding: CGFloat = 14
    static let symbolSize: CGFloat = 12

    /// Room for the level bar beside the notch: the part of the wing under the cutout, the bar
    /// and a margin before the rounded outer corner.
    @MainActor
    static var preferredRightWingWidth: CGFloat {
        barLeadingPadding + barWidth + barTrailingPadding
    }
}

/// Volume / brightness level in the idle wings: the symbol on the left, the level bar on the right.
struct IdleHUDView: View {
    let hud: HUDOverlayState
    let accent: Color
    let wingLayout: IdleWingLayout

    var body: some View {
        IdleWingContainer(
            wingLayout: wingLayout,
            leading: {
                HUDSymbolImage(hud: hud, size: IdleHUDMetrics.symbolSize)
                    .padding(.trailing, NotchFlowConstants.idleWingInnerOverlap)
            },
            trailing: {
                HUDLevelBar(level: hud.displayLevel, accent: accent)
                    .frame(width: IdleHUDMetrics.barWidth, height: IdleHUDMetrics.barHeight)
                    .padding(.leading, NotchFlowConstants.idleWingInnerOverlap + IdleHUDMetrics.barLeadingPadding)
                    .padding(.trailing, IdleHUDMetrics.barTrailingPadding)
            }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hud.accessibilityLabel)
        .accessibilityValue(hud.accessibilityValue)
    }
}

struct HUDSymbolImage: View {
    let hud: HUDOverlayState
    let size: CGFloat

    var body: some View {
        Image(systemName: hud.symbolName)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(IslandStyle.primaryText)
            .frame(width: size * 1.6, height: size * 1.6)
    }
}

/// A rounded level bar. The fill follows the level with a short ease, or jumps with Reduce Motion.
struct HUDLevelBar: View {
    let level: Double
    let accent: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.18))
                Capsule(style: .continuous)
                    .fill(accent)
                    .frame(width: fillWidth(in: proxy.size))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: level)
    }

    private func fillWidth(in size: CGSize) -> CGFloat {
        let clamped = min(max(level, 0), 1)
        guard clamped > 0 else { return 0 }
        // Never thinner than the bar is tall, so a low level still reads as a rounded dot.
        return max(size.height, size.width * clamped)
    }
}

extension HUDOverlayState {
    var accessibilityLabel: String {
        switch kind {
        case .volume: loc("Volume")
        case .brightness: loc("Brightness")
        }
    }

    var accessibilityValue: String {
        if isMuted { return loc("Sound muted") }
        return value.formatted(.percent.precision(.fractionLength(0)))
    }
}
