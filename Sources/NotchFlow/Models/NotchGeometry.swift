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
        // Left-wing width already drops to 0 when the app menu is too wide; keep the right wing visible.
        idleLeftWingWidth == 0 && idleRightWingWidth == 0
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

  /// Expanded hit target for pointer proximity. `forExit: true` uses a looser rect so hover does not flicker off.
    func hoverProximityRect(forExit: Bool) -> CGRect {
        if hasPhysicalNotch {
            let horizontal = NotchFlowConstants.hoverNotchHorizontalExpand
                + (forExit ? NotchFlowConstants.hoverProximityHysteresisPadding : 0)
            let vertical = NotchFlowConstants.hoverNotchVerticalExpand
                + (forExit ? NotchFlowConstants.hoverProximityHysteresisPadding : 0)
            return hoverTriggerRect.insetBy(dx: -horizontal, dy: -vertical)
        }

        let padding = NotchFlowConstants.hoverExpandThreshold
            + (forExit ? NotchFlowConstants.hoverProximityHysteresisPadding : 0)
        return hoverTriggerRect.insetBy(dx: -padding, dy: -padding)
    }

    /// Width reserved for the leading wing slot so hiding the wing does not shift the notch cutout.
    var idleLeftSlotWidth: CGFloat {
        hasPhysicalNotch ? NotchFlowConstants.idleWingProtrusion : idleLeftWingWidth
    }

    func idleLeftSlotFrameWidth(
        innerOverlap: CGFloat = NotchFlowConstants.idleWingInnerOverlap
    ) -> CGFloat {
        guard idleLeftSlotWidth > 0 else { return 0 }
        return idleLeftSlotWidth + innerOverlap
    }

    func idleCenterClearWidth(
        innerOverlap: CGFloat = NotchFlowConstants.idleWingInnerOverlap
    ) -> CGFloat {
        let leftOverlap = idleLeftSlotWidth > 0 ? innerOverlap : 0
        let rightOverlap = idleRightWingWidth > 0 ? innerOverlap : 0
        return max(0, physicalNotchCutoutWidth - leftOverlap - rightOverlap)
    }

    func idleRightSlotFrameWidth(
        innerOverlap: CGFloat = NotchFlowConstants.idleWingInnerOverlap
    ) -> CGFloat {
        guard idleRightWingWidth > 0 else { return 0 }
        return idleRightWingWidth + innerOverlap
    }

    func idleWingLayout(
        innerOverlap: CGFloat = NotchFlowConstants.idleWingInnerOverlap
    ) -> IdleWingLayout {
        let leftSlotWidth = idleLeftSlotFrameWidth(innerOverlap: innerOverlap)
        let centerClearWidth = idleCenterClearWidth(innerOverlap: innerOverlap)
        let rightSlotWidth = idleRightSlotFrameWidth(innerOverlap: innerOverlap)
        return IdleWingLayout(
            visibleLeftWidth: idleLeftWingWidth,
            visibleRightWidth: idleRightWingWidth,
            leftSlotWidth: leftSlotWidth,
            centerClearWidth: centerClearWidth,
            rightSlotWidth: rightSlotWidth,
            panelWidth: idleSize.width,
            panelHeight: idleSize.height
        )
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
            // Keep the notch cutout at a fixed screen position; only toggle wing visibility.
            y = screenTopY - size.height
            x = notchLeftX - idleLeftSlotWidth
        } else {
            y = screenTopY - size.height
            x = screenMidX - size.width / 2
        }

        return CGRect(
            x: x.rounded(.toNearestOrAwayFromZero),
            y: y.rounded(.toNearestOrAwayFromZero),
            width: size.width.rounded(.toNearestOrAwayFromZero),
            height: size.height.rounded(.down)
        )
    }
}

struct IdleWingLayout: Equatable {
    let visibleLeftWidth: CGFloat
    let visibleRightWidth: CGFloat
    let leftSlotWidth: CGFloat
    let centerClearWidth: CGFloat
    let rightSlotWidth: CGFloat
    let panelWidth: CGFloat
    let panelHeight: CGFloat
}

extension NotchGeometry {
    @MainActor
    static func idlePanelHeight(notchTopInset: CGFloat) -> CGFloat {
        max(0, notchTopInset - NotchFlowConstants.idleWingVerticalTrim).rounded(.down)
    }

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
        let idleWidth: CGFloat
        if hasNotch {
            idleWidth = cutoutWidth + defaultWingWidth + rightWingWidth
        } else {
            idleWidth = cutoutWidth + leftWingWidth + rightWingWidth
        }

        let contentHeight = NotchFlowConstants.minimumExpandedContentHeight

        let expandedHeight = NotchFlowConstants.expandedTotalHeight(forContentHeight: contentHeight)
        let configuredWidth = settings.isPremiumEnabled
            ? min(settings.customIslandWidth, NotchFlowConstants.maxExpandedWidth)
            : NotchFlowConstants.defaultExpandedWidth
        let tabBarMinimumWidth = Self.minimumExpandedWidthForTabBar(cutoutWidth: cutoutWidth)
        let expandedWidth = max(
            configuredWidth,
            cutoutWidth + defaultWingWidth * 2,
            tabBarMinimumWidth
        ).rounded()

        // Match the physical notch cutout in the menu bar — no reach into page content.
        let hoverTriggerRect: CGRect
        if hasNotch, let notchLeftX {
            hoverTriggerRect = CGRect(
                x: notchLeftX,
                y: frame.maxY - notchTopInset,
                width: cutoutWidth,
                height: notchTopInset
            )
        } else {
            let hoverTriggerWidth = NotchFlowConstants.hoverTriggerWidth
            let hoverTriggerHeight = max(notchTopInset, NotchFlowConstants.virtualCapsuleHeight)
            hoverTriggerRect = CGRect(
                x: frame.midX - hoverTriggerWidth / 2,
                y: frame.maxY - hoverTriggerHeight,
                width: hoverTriggerWidth,
                height: hoverTriggerHeight
            )
        }

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
                height: Self.idlePanelHeight(notchTopInset: notchTopInset)
            ),
            physicalNotchCutoutWidth: cutoutWidth,
            idleLeftWingWidth: leftWingWidth,
            idleRightWingWidth: rightWingWidth,
            appMenuRightEdgeX: hasNotch ? appMenuRightEdgeX : nil,
            notchLeftX: notchLeftX
        )
    }

    func withExpandedHeight(_ height: CGFloat) -> NotchGeometry {
        NotchGeometry(
            screenIdentifier: screenIdentifier,
            hasPhysicalNotch: hasPhysicalNotch,
            hoverTriggerRect: hoverTriggerRect,
            screenTopY: screenTopY,
            screenMidX: screenMidX,
            notchTopInset: notchTopInset,
            expandedSize: CGSize(width: expandedSize.width, height: height.rounded(.toNearestOrAwayFromZero)),
            idleSize: idleSize,
            physicalNotchCutoutWidth: physicalNotchCutoutWidth,
            idleLeftWingWidth: idleLeftWingWidth,
            idleRightWingWidth: idleRightWingWidth,
            appMenuRightEdgeX: appMenuRightEdgeX,
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
