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
    let idleLeftWingWidth: CGFloat
    let idleRightWingWidth: CGFloat
    /// Right edge of the frontmost app's left menu cluster, when known.
    let appMenuRightEdgeX: CGFloat?
    /// Screen X of the left edge of the hardware notch cutout.
    let notchLeftX: CGFloat?

    var shouldHideIdleForMenuOverlap: Bool {
        guard let notchLeftX, let appMenuRightEdgeX else { return false }
        return appMenuRightEdgeX + NotchFlowConstants.menuOverlapMargin > notchLeftX
    }

    var contentTopInset: CGFloat {
        hasPhysicalNotch ? notchTopInset : 0
    }

    var notchCutoutWidth: CGFloat {
        physicalNotchCutoutWidth
    }

    /// Spacer width between tab groups; equals the physical notch cutout.
    var expandedTabNotchGap: CGFloat {
        physicalNotchCutoutWidth
    }

    static func minimumExpandedWidthForTabBar(cutoutWidth: CGFloat) -> CGFloat {
        let leading = CGFloat(IslandModule.leadingTabs.count) * NotchFlowConstants.expandedTabSlotWidth
        let trailing = CGFloat(IslandModule.trailingTabs.count) * NotchFlowConstants.expandedTabSlotWidth
        let horizontalPadding: CGFloat = 20
        let minimumForTrailingClearance = cutoutWidth + 2 * trailing + horizontalPadding
        let minimumForAllTabs = leading + cutoutWidth + trailing + horizontalPadding
        return max(minimumForTrailingClearance, minimumForAllTabs).rounded(.up)
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
            x = notchLeftX - idleLeftWingWidth
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
    static func make(
        for screen: NSScreen,
        settings: NotchSettings,
        appMenuRightEdgeX: CGFloat? = nil
    ) -> NotchGeometry {
        let frame = screen.frame
        let safeInsets = screen.safeAreaInsets
        let hasNotch = safeInsets.top > 0
        let notchTopInset = hasNotch ? safeInsets.top : 0

        let hoverTriggerWidth = NotchFlowConstants.hoverTriggerWidth
        let hoverTriggerHeight = max(notchTopInset, NotchFlowConstants.virtualCapsuleHeight)

        let notchBounds = notchBounds(for: screen)
        let cutoutWidth = notchBounds.width
        let notchLeftX = notchBounds.leftX

        let defaultWingWidth = NotchFlowConstants.idleWingProtrusion
        let (leftWingWidth, rightWingWidth) = idleWingWidths(
            settings: settings,
            defaultWing: defaultWingWidth,
            notchLeftX: notchLeftX,
            hasNotch: hasNotch,
            appMenuRightEdgeX: appMenuRightEdgeX
        )
        let idleWidth = cutoutWidth + leftWingWidth + rightWingWidth

        let contentHeight = settings.isPremiumEnabled
            ? settings.customIslandHeight
            : NotchFlowConstants.defaultExpandedContentHeight

        let expandedHeight = (
            notchTopInset + contentHeight + NotchFlowConstants.expandedVerticalPadding * 2
        ).rounded()
        let configuredWidth = settings.isPremiumEnabled
            ? min(settings.customIslandWidth, NotchFlowConstants.maxExpandedWidth)
            : NotchFlowConstants.defaultExpandedWidth
        let tabBarMinimumWidth = Self.minimumExpandedWidthForTabBar(cutoutWidth: cutoutWidth)
        let expandedWidth = max(
            configuredWidth,
            cutoutWidth + defaultWingWidth * 2,
            tabBarMinimumWidth
        ).rounded()

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
            idleLeftWingWidth: leftWingWidth,
            idleRightWingWidth: rightWingWidth,
            appMenuRightEdgeX: hasNotch ? appMenuRightEdgeX : nil,
            notchLeftX: notchLeftX
        )
    }

    @MainActor
    static func idleWingWidths(
        settings: NotchSettings,
        defaultWing: CGFloat,
        notchLeftX: CGFloat?,
        hasNotch: Bool,
        appMenuRightEdgeX: CGFloat?
    ) -> (left: CGFloat, right: CGFloat) {
        guard hasNotch else {
            return (defaultWing, defaultWing)
        }

        if settings.avoidMenuOverlap, let appMenuRightEdgeX, let notchLeftX {
            let left = idleLeftWingWidth(
                defaultWing: defaultWing,
                notchLeftX: notchLeftX,
                appMenuRightEdgeX: appMenuRightEdgeX
            )
            return (left, defaultWing)
        }

        return (defaultWing, defaultWing)
    }

    /// All-or-nothing: if the app menu would sit under the full-size wing, hide the wing entirely.
    static func idleLeftWingWidth(
        defaultWing: CGFloat,
        notchLeftX: CGFloat?,
        appMenuRightEdgeX: CGFloat?
    ) -> CGFloat {
        guard let notchLeftX, let appMenuRightEdgeX else {
            return defaultWing
        }

        let available = notchLeftX - appMenuRightEdgeX - NotchFlowConstants.menuOverlapMargin
        return available >= defaultWing ? defaultWing : 0
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
