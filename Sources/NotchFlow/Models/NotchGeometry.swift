import AppKit
import Foundation

/// Where the island attaches on a given display.
enum IslandAnchor: Equatable, Sendable {
    /// Classic MacBook notch: idle wings wrap the hardware cutout, the expanded island grows from it.
    case hardwareNotch
    /// No cutout at all (Mac mini / Studio / iMac / external displays / notch-less MacBooks):
    /// a virtual notch drawn into the middle of the menu bar.
    case menuBarCapsule
    /// The display reserves a top safe area around a system-owned cutout (e.g. a Dynamic Island)
    /// whose position we know. Idle wings sit beside it; everything taller hangs below the menu bar
    /// so the system island is never covered.
    case besideSystemIsland
    /// The display reserves a top safe area but does not describe where the cutout is.
    /// Everything hangs below the reserved band, centered on the screen.
    case belowSystemIsland
}

/// Everything `NotchGeometry` needs to know about a display. Captured once from `NSScreen`
/// (or written by hand in tests) so geometry is a pure function of these values.
struct ScreenMetrics: Equatable, Sendable {
    var identifier: String
    var frame: CGRect
    var visibleFrame: CGRect
    /// `NSScreen.safeAreaInsets.top`; > 0 on displays with a camera housing in the menu bar.
    var safeAreaTop: CGFloat
    var auxiliaryTopLeftArea: CGRect?
    var auxiliaryTopRightArea: CGRect?
    var backingScaleFactor: CGFloat

    init(
        identifier: String,
        frame: CGRect,
        visibleFrame: CGRect? = nil,
        safeAreaTop: CGFloat = 0,
        auxiliaryTopLeftArea: CGRect? = nil,
        auxiliaryTopRightArea: CGRect? = nil,
        backingScaleFactor: CGFloat = 2
    ) {
        self.identifier = identifier
        self.frame = frame
        self.visibleFrame = visibleFrame ?? frame
        self.safeAreaTop = safeAreaTop
        self.auxiliaryTopLeftArea = auxiliaryTopLeftArea
        self.auxiliaryTopRightArea = auxiliaryTopRightArea
        self.backingScaleFactor = backingScaleFactor
    }

    /// Height of the menu bar this display keeps clear of windows. 0 when the menu bar
    /// auto-hides or the display has no menu bar ("Displays have separate Spaces" off).
    var reservedMenuBarHeight: CGFloat {
        max(0, frame.maxY - visibleFrame.maxY)
    }

    /// Debug override: `NOTCHFLOW_SIMULATE_NO_NOTCH=1` makes every display look notch-less,
    /// so the menu-bar capsule can be exercised on a notched MacBook.
    static let simulateNoNotchEnvironmentKey = "NOTCHFLOW_SIMULATE_NO_NOTCH"

    static let isSimulatingNoNotch: Bool =
        ProcessInfo.processInfo.environment[simulateNoNotchEnvironmentKey] == "1"

    /// The same display with its top cutout removed (what a notch-less Mac reports).
    func withoutTopCutout() -> ScreenMetrics {
        var copy = self
        copy.safeAreaTop = 0
        copy.auxiliaryTopLeftArea = nil
        copy.auxiliaryTopRightArea = nil
        return copy
    }
}

extension ScreenMetrics {
    @MainActor
    init(screen: NSScreen, simulateNoNotch: Bool = ScreenMetrics.isSimulatingNoNotch) {
        self.init(
            identifier: screen.localizedName,
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
            auxiliaryTopRightArea: screen.auxiliaryTopRightArea,
            backingScaleFactor: screen.backingScaleFactor
        )
        if simulateNoNotch {
            self = withoutTopCutout()
        }
    }
}

/// What occupies the top-center of a display.
enum TopCutout: Equatable, Sendable {
    /// Nothing: the menu bar runs uninterrupted across the top.
    case none
    /// A MacBook camera notch. `leftX`/`width` already include `notchWidthOverlapFudge`.
    case hardwareNotch(leftX: CGFloat, width: CGFloat)
    /// A reserved top band that is not a classic notch (e.g. a Dynamic Island).
    /// `gap` is the uncovered span between the auxiliary areas when the system reports one.
    case systemIsland(gap: CGRect?)
}

struct NotchGeometry: Equatable {
    let screenIdentifier: String
    let anchor: IslandAnchor
    let hasPhysicalNotch: Bool
    let hoverTriggerRect: CGRect
    let screenTopY: CGFloat
    let screenMidX: CGFloat
    /// Top edge the idle wings hang from (the screen top, except below an unknown system island).
    let idleTopY: CGFloat
    /// Top edge the expanded island and drop banners hang from.
    let islandTopY: CGFloat
    let notchTopInset: CGFloat
    private(set) var expandedSize: CGSize
    let idleSize: CGSize
    /// Hardware cutout width, or the width of the virtual notch on displays without one.
    let physicalNotchCutoutWidth: CGFloat
    let idleLeftWingWidth: CGFloat
    let idleRightWingWidth: CGFloat
    /// Right edge of the frontmost app's left menu cluster, when known.
    let appMenuRightEdgeX: CGFloat?
    /// Screen X of the left edge of the hardware notch cutout (or of the virtual notch).
    let notchLeftX: CGFloat?
    /// False when the user turned the island off for displays without a notch:
    /// no hover trigger and no idle wings; the menu bar icon still opens it.
    let allowsAutomaticPresentation: Bool
    /// Idle capsule would sit on top of menus, or the menu bar it lives in is hidden
    /// (auto-hide, full screen). Never set for a hardware notch.
    let suppressesIdleCapsule: Bool

    var shouldHideIdleForMenuOverlap: Bool {
        // Left-wing width already drops to 0 when the app menu is too wide; keep the right wing visible.
        (idleLeftWingWidth == 0 && idleRightWingWidth == 0) || suppressesIdleCapsule
    }

    /// The idle panel must paint its own center: there is no black hardware behind it.
    var fillsIdleCenter: Bool {
        switch anchor {
        case .hardwareNotch, .besideSystemIsland: false
        case .menuBarCapsule, .belowSystemIsland: true
        }
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
    /// Every anchor uses the notch forgiveness: the trigger lives in the menu bar and must not
    /// reach far into window content below it.
    func hoverProximityRect(forExit: Bool) -> CGRect {
        let horizontal = NotchFlowConstants.hoverNotchHorizontalExpand
            + (forExit ? NotchFlowConstants.hoverProximityHysteresisPadding : 0)
        let vertical = NotchFlowConstants.hoverNotchVerticalExpand
            + (forExit ? NotchFlowConstants.hoverProximityHysteresisPadding : 0)
        return hoverTriggerRect.insetBy(dx: -horizontal, dy: -vertical)
    }

    /// Width reserved for the leading wing slot so hiding the wing does not shift the notch cutout.
    var idleLeftSlotWidth: CGFloat {
        hasPhysicalNotch ? NotchFlowConstants.idleWingProtrusion : idleLeftWingWidth
    }

    func resolvedIdleLeftWingWidth(override: CGFloat?) -> CGFloat {
        let base = idleLeftSlotWidth
        guard base > 0, let override else { return base }
        return max(base, override)
    }

    func idleLeftSlotFrameWidth(
        innerOverlap: CGFloat = NotchFlowConstants.idleWingInnerOverlap,
        leftWingWidth: CGFloat? = nil
    ) -> CGFloat {
        let wing = resolvedIdleLeftWingWidth(override: leftWingWidth)
        guard wing > 0 else { return 0 }
        return wing + innerOverlap
    }

    func idleCenterClearWidth(
        innerOverlap: CGFloat = NotchFlowConstants.idleWingInnerOverlap,
        leftWingWidth: CGFloat? = nil,
        rightWingWidth: CGFloat? = nil
    ) -> CGFloat {
        let left = resolvedIdleLeftWingWidth(override: leftWingWidth)
        let right = resolvedIdleRightWingWidth(override: rightWingWidth)
        let leftOverlap = left > 0 ? innerOverlap : 0
        let rightOverlap = right > 0 ? innerOverlap : 0
        return max(0, physicalNotchCutoutWidth - leftOverlap - rightOverlap)
    }

    func idleRightSlotFrameWidth(
        innerOverlap: CGFloat = NotchFlowConstants.idleWingInnerOverlap,
        rightWingWidth: CGFloat? = nil
    ) -> CGFloat {
        let wing = resolvedIdleRightWingWidth(override: rightWingWidth)
        guard wing > 0 else { return 0 }
        return wing + innerOverlap
    }

    /// Content (e.g. a notification peek) may request a wider right wing; never narrower than default.
    func resolvedIdleRightWingWidth(override: CGFloat?) -> CGFloat {
        guard idleRightWingWidth > 0, let override else { return idleRightWingWidth }
        return max(idleRightWingWidth, override)
    }

    func idleWingLayout(
        innerOverlap: CGFloat = NotchFlowConstants.idleWingInnerOverlap,
        leftWingWidth: CGFloat? = nil,
        rightWingWidth: CGFloat? = nil
    ) -> IdleWingLayout {
        let resolvedLeftWing = resolvedIdleLeftWingWidth(override: leftWingWidth)
        let resolvedRightWing = resolvedIdleRightWingWidth(override: rightWingWidth)
        let leftSlotWidth = idleLeftSlotFrameWidth(innerOverlap: innerOverlap, leftWingWidth: leftWingWidth)
        let centerClearWidth = idleCenterClearWidth(
            innerOverlap: innerOverlap,
            leftWingWidth: leftWingWidth,
            rightWingWidth: rightWingWidth
        )
        let rightSlotWidth = idleRightSlotFrameWidth(innerOverlap: innerOverlap, rightWingWidth: rightWingWidth)
        return IdleWingLayout(
            // The slot keeps its width so the notch cutout does not move, but a wing hidden for
            // menu overlap must not be drawn over the app menu.
            visibleLeftWidth: idleLeftWingWidth > 0 ? resolvedLeftWing : 0,
            visibleRightWidth: resolvedRightWing,
            leftSlotWidth: leftSlotWidth,
            centerClearWidth: centerClearWidth,
            rightSlotWidth: rightSlotWidth,
            panelWidth: idleSize.width - idleLeftSlotWidth - idleRightWingWidth + resolvedLeftWing + resolvedRightWing,
            panelHeight: idleSize.height
        )
    }

    func frame(
        isExpanded: Bool,
        isIdle: Bool = false,
        idleLeftWingWidth leftWingOverride: CGFloat? = nil,
        idleRightWingWidth rightWingOverride: CGFloat? = nil,
        idleBannerWidth bannerWidthOverride: CGFloat? = nil
    ) -> CGRect {
        let size: CGSize
        if isExpanded {
            size = expandedSize
        } else if isIdle, let bannerWidth = bannerWidthOverride {
            size = CGSize(
                width: bannerWidth,
                height: NotchFlowConstants.dropBannerHeight(
                    topInset: max(notchTopInset, idleSize.height),
                    contentHeight: max(
                        NotchFlowConstants.dropBannerContentHeight,
                        NotchFlowConstants.incomingCallDropContentHeight
                    )
                )
            )
        } else if isIdle {
            let resolvedLeftWing = resolvedIdleLeftWingWidth(override: leftWingOverride)
            let resolvedRightWing = resolvedIdleRightWingWidth(override: rightWingOverride)
            size = CGSize(
                width: idleSize.width - idleLeftSlotWidth - idleRightWingWidth + resolvedLeftWing + resolvedRightWing,
                height: idleSize.height
            )
        } else {
            return .zero
        }

        let y: CGFloat
        let x: CGFloat

        if isExpanded, let notchLeftX {
            // Centered on the (hardware or virtual) notch.
            y = islandTopY - size.height
            x = notchLeftX + physicalNotchCutoutWidth / 2 - size.width / 2
        } else if isIdle, bannerWidthOverride != nil {
            // Center-attached incoming-call banner under the hardware cutout.
            y = islandTopY - size.height
            if let notchLeftX {
                x = notchLeftX + physicalNotchCutoutWidth / 2 - size.width / 2
            } else {
                x = screenMidX - size.width / 2
            }
        } else if isIdle, let notchLeftX {
            // Keep the notch cutout at a fixed screen position; only toggle wing visibility.
            let resolvedLeftWing = resolvedIdleLeftWingWidth(override: leftWingOverride)
            y = idleTopY - size.height
            x = notchLeftX - resolvedLeftWing
        } else {
            y = (isExpanded ? islandTopY : idleTopY) - size.height
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

// MARK: - Inputs

extension NotchGeometry {
    /// User preferences that shape the geometry, copied out of `NotchSettings` so geometry can be
    /// computed (and tested) without touching the shared settings object.
    struct Options: Equatable, Sendable {
        var avoidMenuOverlap: Bool
        var isPremiumEnabled: Bool
        var customIslandWidth: CGFloat
        var nonNotchPlacement: NonNotchIslandPlacement

        init(
            avoidMenuOverlap: Bool = true,
            isPremiumEnabled: Bool = false,
            customIslandWidth: CGFloat = NotchFlowConstants.defaultExpandedWidth,
            nonNotchPlacement: NonNotchIslandPlacement = .topCenter
        ) {
            self.avoidMenuOverlap = avoidMenuOverlap
            self.isPremiumEnabled = isPremiumEnabled
            self.customIslandWidth = customIslandWidth
            self.nonNotchPlacement = nonNotchPlacement
        }

        @MainActor
        init(settings: NotchSettings) {
            self.init(
                avoidMenuOverlap: settings.avoidMenuOverlap,
                isPremiumEnabled: settings.isPremiumEnabled,
                customIslandWidth: settings.customIslandWidth,
                nonNotchPlacement: settings.nonNotchIslandPlacement
            )
        }
    }

    /// What is currently in the menu bar around the island. All values are screen X coordinates.
    struct MenuBarContext: Equatable, Sendable {
        /// Right edge of the frontmost app's menus (File, Edit, …).
        var appMenuRightEdgeX: CGFloat?
        /// Left edge of the status items (clock, Wi-Fi, third-party icons) when they reach the island.
        var statusItemsLeftEdgeX: CGFloat?
        /// A full-screen window owns this display, so its menu bar only slides in on demand.
        var isFullScreenActive: Bool

        init(appMenuRightEdgeX: CGFloat? = nil, statusItemsLeftEdgeX: CGFloat? = nil, isFullScreenActive: Bool = false) {
            self.appMenuRightEdgeX = appMenuRightEdgeX
            self.statusItemsLeftEdgeX = statusItemsLeftEdgeX
            self.isFullScreenActive = isFullScreenActive
        }
    }
}

// MARK: - Cutout detection

extension NotchGeometry {
    /// Narrowest auxiliary-area gap still treated as a MacBook camera notch. Notches measure
    /// ~150–200 pt depending on the display scaling; anything narrower is a different cutout.
    static let minimumHardwareNotchWidth: CGFloat = 120
    /// Widest gap still treated as a notch; wider means the auxiliary areas describe something else.
    static let maximumHardwareNotchWidth: CGFloat = 320
    /// A notch is centered on the display; allow for odd-width frames and rounding.
    static let hardwareNotchCenterTolerance: CGFloat = 24

    /// Classifies the top-center of a display.
    ///
    /// A MacBook notch is the only cutout we wrap: macOS reports a top safe area *and* two
    /// auxiliary areas whose gap is notch-sized and centered. Any other combination with a safe
    /// area (no auxiliary areas, a narrow gap such as a Dynamic Island, an off-center gap) is a
    /// system-owned cutout we must not cover. We cannot test those Macs, so they get the
    /// conservative capsule placement instead of guessing at their shape.
    static func classifyTopCutout(_ metrics: ScreenMetrics) -> TopCutout {
        guard metrics.safeAreaTop > 0 else { return .none }

        guard let leftArea = metrics.auxiliaryTopLeftArea,
              let rightArea = metrics.auxiliaryTopRightArea else {
            return .systemIsland(gap: nil)
        }

        let gapWidth = rightArea.minX - leftArea.maxX
        guard gapWidth > 0 else { return .systemIsland(gap: nil) }

        let gap = CGRect(
            x: leftArea.maxX,
            y: metrics.frame.maxY - metrics.safeAreaTop,
            width: gapWidth,
            height: metrics.safeAreaTop
        )
        let isCentered = abs(gap.midX - metrics.frame.midX) <= hardwareNotchCenterTolerance
        guard gapWidth >= minimumHardwareNotchWidth,
              gapWidth <= maximumHardwareNotchWidth,
              isCentered else {
            return .systemIsland(gap: gap)
        }

        let fudge = NotchFlowConstants.notchWidthOverlapFudge
        return .hardwareNotch(leftX: leftArea.maxX - fudge / 2, width: gapWidth + fudge)
    }

    /// Horizontal span the idle capsule can occupy on a display without a hardware notch,
    /// used to look for menu bar items under it. `nil` when nothing is drawn into the menu bar.
    static func menuBarCapsuleSpan(for metrics: ScreenMetrics) -> ClosedRange<CGFloat>? {
        let center: (leftX: CGFloat, width: CGFloat)
        switch classifyTopCutout(metrics) {
        case .hardwareNotch, .systemIsland(gap: nil):
            return nil
        case .none:
            center = virtualNotch(for: metrics)
        case .systemIsland(let gap?):
            center = virtualNotch(besideSystemIsland: gap, scale: metrics.backingScaleFactor)
        }
        let reach = NotchFlowConstants.idleWingProtrusion + NotchFlowConstants.menuOverlapMargin
        return (center.leftX - reach)...(center.leftX + center.width + reach)
    }

    private static func pixelAligned(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        guard scale > 0 else { return value.rounded() }
        return (value * scale).rounded() / scale
    }

    private static func virtualNotch(for metrics: ScreenMetrics) -> (leftX: CGFloat, width: CGFloat) {
        let width = NotchFlowConstants.menuBarCapsuleCenterWidth
        return (pixelAligned(metrics.frame.midX - width / 2, scale: metrics.backingScaleFactor), width)
    }

    private static func virtualNotch(besideSystemIsland gap: CGRect, scale: CGFloat) -> (leftX: CGFloat, width: CGFloat) {
        let clearance = NotchFlowConstants.systemIslandClearance
        return (
            pixelAligned(gap.minX - clearance, scale: scale),
            pixelAligned(gap.width + clearance * 2, scale: scale)
        )
    }
}

// MARK: - Factory

extension NotchGeometry {
    @MainActor
    static func idlePanelHeight(notchTopInset: CGFloat) -> CGFloat {
        max(0, notchTopInset - NotchFlowConstants.idleWingVerticalTrim).rounded(.down)
    }

    /// Geometry for one display. Pure: everything comes from the arguments, so tests can feed
    /// fixtures for any Mac (`ScreenMetrics(screen:)` captures a live display).
    @MainActor
    static func make(
        metrics: ScreenMetrics,
        options: Options,
        context: MenuBarContext = MenuBarContext()
    ) -> NotchGeometry {
        switch classifyTopCutout(metrics) {
        case .hardwareNotch(let leftX, let width):
            return makeHardwareNotch(metrics: metrics, options: options, context: context, notchLeftX: leftX, cutoutWidth: width)
        case .none:
            return makeMenuBarCapsule(metrics: metrics, options: options, context: context)
        case .systemIsland(let gap?):
            return makeBesideSystemIsland(metrics: metrics, options: options, context: context, gap: gap)
        case .systemIsland(nil):
            return makeBelowSystemIsland(metrics: metrics, options: options, context: context)
        }
    }

    private static func expandedHeight() -> CGFloat {
        NotchFlowConstants.expandedTotalHeight(forContentHeight: NotchFlowConstants.minimumExpandedContentHeight)
    }

    private static func expandedWidth(options: Options, cutoutWidth: CGFloat) -> CGFloat {
        let defaultWingWidth = NotchFlowConstants.idleWingProtrusion
        let configuredWidth = options.isPremiumEnabled
            ? min(options.customIslandWidth, NotchFlowConstants.maxExpandedWidth)
            : NotchFlowConstants.defaultExpandedWidth
        let tabBarMinimumWidth = minimumExpandedWidthForTabBar(cutoutWidth: cutoutWidth)
        return max(
            configuredWidth,
            cutoutWidth + defaultWingWidth * 2,
            tabBarMinimumWidth
        ).rounded()
    }

    /// Expanded width on displays without a hardware notch: same as a notched MacBook so module
    /// layouts look identical everywhere.
    private static func notchlessExpandedWidth(options: Options) -> CGFloat {
        expandedWidth(options: options, cutoutWidth: NotchFlowConstants.defaultNotchCutoutWidth)
    }

    @MainActor
    private static func makeHardwareNotch(
        metrics: ScreenMetrics,
        options: Options,
        context: MenuBarContext,
        notchLeftX: CGFloat,
        cutoutWidth: CGFloat
    ) -> NotchGeometry {
        let frame = metrics.frame
        let notchTopInset = metrics.safeAreaTop
        let defaultWingWidth = NotchFlowConstants.idleWingProtrusion
        let (leftWingWidth, rightWingWidth) = idleWingWidths(
            avoidMenuOverlap: options.avoidMenuOverlap,
            defaultWing: defaultWingWidth,
            notchLeftX: notchLeftX,
            hasNotch: true,
            appMenuRightEdgeX: context.appMenuRightEdgeX
        )
        let idleWidth = cutoutWidth + defaultWingWidth + rightWingWidth

        // Match the physical notch cutout in the menu bar — no reach into page content.
        let hoverTriggerRect = CGRect(
            x: notchLeftX,
            y: frame.maxY - notchTopInset,
            width: cutoutWidth,
            height: notchTopInset
        )

        return NotchGeometry(
            screenIdentifier: metrics.identifier,
            anchor: .hardwareNotch,
            hasPhysicalNotch: true,
            hoverTriggerRect: hoverTriggerRect,
            screenTopY: frame.maxY,
            screenMidX: frame.midX,
            idleTopY: frame.maxY,
            islandTopY: frame.maxY,
            notchTopInset: notchTopInset,
            expandedSize: CGSize(
                width: expandedWidth(options: options, cutoutWidth: cutoutWidth),
                height: expandedHeight()
            ),
            idleSize: CGSize(
                width: idleWidth.rounded(.toNearestOrAwayFromZero),
                height: idlePanelHeight(notchTopInset: notchTopInset)
            ),
            physicalNotchCutoutWidth: cutoutWidth,
            idleLeftWingWidth: leftWingWidth,
            idleRightWingWidth: rightWingWidth,
            appMenuRightEdgeX: context.appMenuRightEdgeX,
            notchLeftX: notchLeftX,
            allowsAutomaticPresentation: true,
            suppressesIdleCapsule: false
        )
    }

    /// No cutout: draw a virtual notch into the middle of the menu bar, exactly as tall as the
    /// menu bar so it never hangs over window content, and hide whatever would cover menus.
    @MainActor
    private static func makeMenuBarCapsule(
        metrics: ScreenMetrics,
        options: Options,
        context: MenuBarContext
    ) -> NotchGeometry {
        let frame = metrics.frame
        let reserved = metrics.reservedMenuBarHeight
        let isMenuBarHidden = reserved <= 0
        let bandHeight = isMenuBarHidden ? NotchFlowConstants.fallbackMenuBarHeight : reserved
        let center = virtualNotch(for: metrics)
        let obstacles = capsuleObstacles(
            options: options,
            context: context,
            centerLeftX: center.leftX,
            centerWidth: center.width
        )

        let hoverTriggerWidth = max(NotchFlowConstants.hoverTriggerWidth, center.width)
        let hoverTriggerRect = CGRect(
            x: frame.midX - hoverTriggerWidth / 2,
            y: frame.maxY - bandHeight,
            width: hoverTriggerWidth,
            height: bandHeight
        )

        return NotchGeometry(
            screenIdentifier: metrics.identifier,
            anchor: .menuBarCapsule,
            hasPhysicalNotch: false,
            hoverTriggerRect: hoverTriggerRect,
            screenTopY: frame.maxY,
            screenMidX: frame.midX,
            idleTopY: frame.maxY,
            islandTopY: frame.maxY,
            notchTopInset: 0,
            expandedSize: CGSize(width: notchlessExpandedWidth(options: options), height: expandedHeight()),
            idleSize: CGSize(
                width: (center.width + obstacles.leftWing + obstacles.rightWing).rounded(.toNearestOrAwayFromZero),
                height: bandHeight.rounded(.down)
            ),
            physicalNotchCutoutWidth: center.width,
            idleLeftWingWidth: obstacles.leftWing,
            idleRightWingWidth: obstacles.rightWing,
            appMenuRightEdgeX: context.appMenuRightEdgeX,
            notchLeftX: center.leftX,
            allowsAutomaticPresentation: options.nonNotchPlacement != .off,
            suppressesIdleCapsule: obstacles.centerBlocked || isMenuBarHidden || context.isFullScreenActive
        )
    }

    /// A system cutout whose gap we know (e.g. a Dynamic Island): idle wings sit in the menu bar
    /// beside it with a little clearance, the gap itself stays uncovered, and the expanded island
    /// hangs below the reserved band so it never overlaps the system island.
    @MainActor
    private static func makeBesideSystemIsland(
        metrics: ScreenMetrics,
        options: Options,
        context: MenuBarContext,
        gap: CGRect
    ) -> NotchGeometry {
        let frame = metrics.frame
        let band = metrics.safeAreaTop
        let center = virtualNotch(besideSystemIsland: gap, scale: metrics.backingScaleFactor)
        let obstacles = capsuleObstacles(
            options: options,
            context: context,
            centerLeftX: center.leftX,
            centerWidth: center.width
        )

        return NotchGeometry(
            screenIdentifier: metrics.identifier,
            anchor: .besideSystemIsland,
            hasPhysicalNotch: false,
            hoverTriggerRect: CGRect(x: center.leftX, y: frame.maxY - band, width: center.width, height: band),
            screenTopY: frame.maxY,
            screenMidX: frame.midX,
            idleTopY: frame.maxY,
            islandTopY: frame.maxY - band,
            notchTopInset: 0,
            expandedSize: CGSize(width: notchlessExpandedWidth(options: options), height: expandedHeight()),
            idleSize: CGSize(
                width: (center.width + obstacles.leftWing + obstacles.rightWing).rounded(.toNearestOrAwayFromZero),
                height: idlePanelHeight(notchTopInset: band)
            ),
            physicalNotchCutoutWidth: center.width,
            idleLeftWingWidth: obstacles.leftWing,
            idleRightWingWidth: obstacles.rightWing,
            appMenuRightEdgeX: context.appMenuRightEdgeX,
            notchLeftX: center.leftX,
            allowsAutomaticPresentation: options.nonNotchPlacement != .off,
            // Wings stay meaningful without their center, so only a covered menu or a
            // full-screen window hides them.
            suppressesIdleCapsule: obstacles.centerBlocked || context.isFullScreenActive
        )
    }

    /// A reserved top band with no description of the cutout: hang a small capsule below the
    /// band, centered, so whatever the system draws up there stays visible.
    @MainActor
    private static func makeBelowSystemIsland(
        metrics: ScreenMetrics,
        options: Options,
        context: MenuBarContext
    ) -> NotchGeometry {
        let frame = metrics.frame
        let topY = frame.maxY - metrics.safeAreaTop
        let capsuleHeight = NotchFlowConstants.fallbackMenuBarHeight
        let center = virtualNotch(for: metrics)
        let wing = NotchFlowConstants.idleWingProtrusion
        let hoverTriggerWidth = max(NotchFlowConstants.hoverTriggerWidth, center.width)

        return NotchGeometry(
            screenIdentifier: metrics.identifier,
            anchor: .belowSystemIsland,
            hasPhysicalNotch: false,
            // Cover the reserved band and the capsule below it.
            hoverTriggerRect: CGRect(
                x: frame.midX - hoverTriggerWidth / 2,
                y: topY - capsuleHeight,
                width: hoverTriggerWidth,
                height: metrics.safeAreaTop + capsuleHeight
            ),
            screenTopY: frame.maxY,
            screenMidX: frame.midX,
            idleTopY: topY,
            islandTopY: topY,
            notchTopInset: 0,
            expandedSize: CGSize(width: notchlessExpandedWidth(options: options), height: expandedHeight()),
            idleSize: CGSize(width: center.width + wing * 2, height: capsuleHeight),
            physicalNotchCutoutWidth: center.width,
            idleLeftWingWidth: wing,
            idleRightWingWidth: wing,
            appMenuRightEdgeX: context.appMenuRightEdgeX,
            notchLeftX: center.leftX,
            allowsAutomaticPresentation: options.nonNotchPlacement != .off,
            suppressesIdleCapsule: context.isFullScreenActive
        )
    }

    /// Which parts of an island drawn into the menu bar would cover app menus or status items.
    /// Wings are all-or-nothing, like the hardware-notch left wing.
    static func capsuleObstacles(
        options: Options,
        context: MenuBarContext,
        centerLeftX: CGFloat,
        centerWidth: CGFloat
    ) -> (leftWing: CGFloat, rightWing: CGFloat, centerBlocked: Bool) {
        let wing = NotchFlowConstants.idleWingProtrusion
        guard options.avoidMenuOverlap else { return (wing, wing, false) }

        let margin = NotchFlowConstants.menuOverlapMargin
        let centerRightX = centerLeftX + centerWidth
        var leftWing = wing
        var rightWing = wing
        var centerBlocked = false

        if let menuEdge = context.appMenuRightEdgeX {
            let available = centerLeftX - menuEdge - margin
            if available < wing { leftWing = 0 }
            if available < 0 { centerBlocked = true }
        }
        if let statusEdge = context.statusItemsLeftEdgeX {
            let available = statusEdge - centerRightX - margin
            if available < wing { rightWing = 0 }
            if available < 0 { centerBlocked = true }
        }
        return (leftWing, rightWing, centerBlocked)
    }

    func withExpandedHeight(_ height: CGFloat) -> NotchGeometry {
        var copy = self
        copy.expandedSize = CGSize(width: expandedSize.width, height: height.rounded(.toNearestOrAwayFromZero))
        return copy
    }

    static func idleWingWidths(
        avoidMenuOverlap: Bool,
        defaultWing: CGFloat,
        notchLeftX: CGFloat?,
        hasNotch: Bool,
        appMenuRightEdgeX: CGFloat?
    ) -> (left: CGFloat, right: CGFloat) {
        guard hasNotch else {
            return (defaultWing, defaultWing)
        }

        if avoidMenuOverlap, let appMenuRightEdgeX, let notchLeftX {
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
}
