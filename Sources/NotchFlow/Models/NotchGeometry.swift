import AppKit
import Foundation

struct NotchGeometry: Equatable {
    let screenIdentifier: String
    let hasPhysicalNotch: Bool
    let hoverTriggerRect: CGRect
    let screenTopY: CGFloat
    let screenMidX: CGFloat
    let notchTopInset: CGFloat
    let expandedSize: CGSize
    let idleSize: CGSize
    let physicalNotchCutoutWidth: CGFloat
    let idleWingWidth: CGFloat
    /// Screen X of the left edge of the hardware notch cutout.
    let notchLeftX: CGFloat?

    var contentTopInset: CGFloat {
        hasPhysicalNotch ? notchTopInset : 0
    }

    var notchCutoutWidth: CGFloat {
        physicalNotchCutoutWidth
    }

    func frame(isExpanded: Bool, isIdle: Bool = false) -> CGRect {
        let size: CGSize
        if isExpanded {
            size = expandedSize
        } else if isIdle {
            size = idleSize
        } else {
            return .zero
        }

        let y: CGFloat
        let x: CGFloat

        if isExpanded, hasPhysicalNotch, let notchLeftX {
            y = screenTopY - size.height
            x = notchLeftX + physicalNotchCutoutWidth / 2 - size.width / 2
        } else if isIdle, let notchLeftX {
            // Anchor wings to notch edges so they protrude into the menu bar.
            y = screenTopY - size.height
            x = notchLeftX - idleWingWidth
        } else {
            y = screenTopY - size.height
            x = screenMidX - size.width / 2
        }

        return CGRect(
            x: x.rounded(.toNearestOrAwayFromZero),
            y: y.rounded(.toNearestOrAwayFromZero),
            width: size.width.rounded(.toNearestOrAwayFromZero),
            height: size.height.rounded(.toNearestOrAwayFromZero)
        )
    }
}

extension NotchGeometry {
    @MainActor
    static func make(for screen: NSScreen, settings: NotchSettings) -> NotchGeometry {
        let frame = screen.frame
        let safeInsets = screen.safeAreaInsets
        let hasNotch = safeInsets.top > 0
        let notchTopInset = hasNotch ? safeInsets.top : 0

        let hoverTriggerWidth = NotchFlowConstants.hoverTriggerWidth
        let hoverTriggerHeight = max(notchTopInset, NotchFlowConstants.virtualCapsuleHeight)

        let notchBounds = notchBounds(for: screen)
        let cutoutWidth = notchBounds.width
        let notchLeftX = notchBounds.leftX

        let wingWidth = NotchFlowConstants.idleWingProtrusion
        let idleWidth = cutoutWidth + wingWidth * 2

        let contentHeight = settings.isPremiumEnabled
            ? settings.customIslandHeight
            : NotchFlowConstants.defaultExpandedContentHeight

        let expandedHeight = (notchTopInset + contentHeight + NotchFlowConstants.expandedVerticalPadding * 2).rounded()
        let configuredWidth = settings.isPremiumEnabled
            ? min(settings.customIslandWidth, NotchFlowConstants.maxExpandedWidth)
            : NotchFlowConstants.defaultExpandedWidth
        let expandedWidth = max(configuredWidth, cutoutWidth + wingWidth * 2).rounded()

        let hoverTriggerRect = CGRect(
            x: frame.midX - hoverTriggerWidth / 2,
            y: frame.maxY - hoverTriggerHeight,
            width: hoverTriggerWidth,
            height: hoverTriggerHeight
        )

        return NotchGeometry(
            screenIdentifier: screen.localizedName,
            hasPhysicalNotch: hasNotch,
            hoverTriggerRect: hoverTriggerRect,
            screenTopY: frame.maxY,
            screenMidX: frame.midX,
            notchTopInset: notchTopInset,
            expandedSize: CGSize(width: expandedWidth, height: expandedHeight),
            idleSize: CGSize(
                width: idleWidth.rounded(.toNearestOrAwayFromZero),
                height: (notchTopInset + NotchFlowConstants.idleBottomBleed).rounded(.toNearestOrAwayFromZero)
            ),
            physicalNotchCutoutWidth: cutoutWidth,
            idleWingWidth: wingWidth,
            notchLeftX: notchLeftX
        )
    }

    @MainActor
    private static func notchBounds(for screen: NSScreen) -> (leftX: CGFloat?, width: CGFloat) {
        guard screen.safeAreaInsets.top > 0,
              let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea else {
            return (nil, NotchFlowConstants.defaultNotchCutoutWidth)
        }

        let width = rightArea.minX - leftArea.maxX + NotchFlowConstants.notchWidthOverlapFudge
        guard width > 0 else {
            return (nil, NotchFlowConstants.defaultNotchCutoutWidth)
        }
        let halfFudge = NotchFlowConstants.notchWidthOverlapFudge / 2
        return (leftArea.maxX - halfFudge, width)
    }
}
