import XCTest
@testable import NotchFlow

/// Geometry on displays without a hardware notch: the menu-bar capsule (Mac mini / Studio / iMac,
/// external monitors, notch-less MacBooks) and the system-island fallbacks (Dynamic Island).
@MainActor
final class NotchlessGeometryTests: XCTestCase {
    private let wing = NotchFlowConstants.idleWingProtrusion
    private let center = NotchFlowConstants.menuBarCapsuleCenterWidth
    private let expandedHeight: CGFloat = 218
    /// Notch-less displays reuse the notched expanded width so modules lay out identically.
    private let notchlessExpandedWidth: CGFloat = 564

    private func geometry(
        _ metrics: ScreenMetrics,
        options: NotchGeometry.Options = NotchGeometry.Options(),
        context: NotchGeometry.MenuBarContext = NotchGeometry.MenuBarContext()
    ) -> NotchGeometry {
        NotchGeometry.make(metrics: metrics, options: options, context: context)
    }

    // MARK: Menu-bar capsule

    func testNotchlessMacGetsCenteredMenuBarCapsule() {
        let metrics = ScreenFixtures.macMini1080p
        XCTAssertEqual(NotchGeometry.classifyTopCutout(metrics), TopCutout.none)

        let geometry = geometry(metrics)
        XCTAssertEqual(geometry.anchor, .menuBarCapsule)
        XCTAssertFalse(geometry.hasPhysicalNotch)
        XCTAssertTrue(geometry.fillsIdleCenter)
        XCTAssertTrue(geometry.allowsAutomaticPresentation)
        XCTAssertFalse(geometry.shouldHideIdleForMenuOverlap)
        XCTAssertEqual(geometry.contentTopInset, 0)
        XCTAssertEqual(geometry.notchLeftX, 960 - center / 2)

        // Exactly as tall as the 24 pt menu bar, flush with the top, centered.
        let idle = geometry.frame(isExpanded: false, isIdle: true)
        XCTAssertEqual(idle, CGRect(x: 960 - center / 2 - wing, y: 1056, width: center + wing * 2, height: 24))
        XCTAssertEqual(idle.midX, 960)

        let expanded = geometry.frame(isExpanded: true)
        XCTAssertEqual(expanded, CGRect(x: 960 - notchlessExpandedWidth / 2, y: 1080 - expandedHeight, width: notchlessExpandedWidth, height: expandedHeight))
    }

    func testCapsuleHoverStaysInsideMenuBarBand() {
        let geometry = geometry(ScreenFixtures.macMini1080p)
        XCTAssertEqual(geometry.hoverTriggerRect, CGRect(x: 860, y: 1056, width: 200, height: 24))

        // Same forgiveness as the notch: a little beyond the menu bar, not deep into windows.
        let enter = geometry.hoverProximityRect(forExit: false)
        XCTAssertEqual(enter.minY, 1056 - NotchFlowConstants.hoverNotchVerticalExpand)
        XCTAssertTrue(enter.contains(CGPoint(x: 960, y: 1079)))
        XCTAssertFalse(enter.contains(CGPoint(x: 960, y: 1000)))
        XCTAssertFalse(enter.contains(CGPoint(x: 700, y: 1070)))
    }

    func testCapsuleOnExternalDisplayUsesThatDisplaysCoordinates() {
        let metrics = ScreenFixtures.externalDisplay
        let geometry = geometry(metrics)
        let idle = geometry.frame(isExpanded: false, isIdle: true)

        XCTAssertEqual(geometry.anchor, .menuBarCapsule)
        XCTAssertEqual(idle.midX, metrics.frame.midX)
        XCTAssertEqual(idle.maxY, metrics.frame.maxY)
        XCTAssertEqual(idle.height, 24)
        XCTAssertTrue(metrics.frame.contains(geometry.frame(isExpanded: true)))
    }

    func testCapsuleIsPixelAlignedForBackingScale() {
        var oddWidth = ScreenFixtures.macMini1080p
        oddWidth.frame = CGRect(x: 0, y: 0, width: 1365, height: 768)
        oddWidth.visibleFrame = CGRect(x: 0, y: 0, width: 1365, height: 744)

        oddWidth.backingScaleFactor = 1
        XCTAssertEqual(geometry(oddWidth).notchLeftX, 623)

        oddWidth.backingScaleFactor = 2
        XCTAssertEqual(geometry(oddWidth).notchLeftX, 622.5)
    }

    func testCapsuleHidesLeftWingWhenAppMenuReachesIt() {
        let leftX = 960 - center / 2
        let margin = NotchFlowConstants.menuOverlapMargin

        let fits = geometry(ScreenFixtures.macMini1080p, context: .init(appMenuRightEdgeX: leftX - margin - wing - 1))
        XCTAssertEqual(fits.idleLeftWingWidth, wing)

        let hidden = geometry(ScreenFixtures.macMini1080p, context: .init(appMenuRightEdgeX: leftX - margin - wing + 1))
        XCTAssertEqual(hidden.idleLeftWingWidth, 0)
        XCTAssertEqual(hidden.idleRightWingWidth, wing)
        XCTAssertFalse(hidden.shouldHideIdleForMenuOverlap)
        // The virtual notch stays put; only the wing disappears (no transparent slot left behind).
        let idle = hidden.frame(isExpanded: false, isIdle: true)
        XCTAssertEqual(idle.minX, leftX)
        XCTAssertEqual(idle.width, center + wing)
        XCTAssertEqual(hidden.idleWingLayout().leftSlotWidth, 0)
    }

    func testCapsuleHidesRightWingWhenStatusItemsReachIt() {
        let rightX = 960 + center / 2
        let margin = NotchFlowConstants.menuOverlapMargin

        let hidden = geometry(ScreenFixtures.macMini1080p, context: .init(statusItemsLeftEdgeX: rightX + margin + wing - 1))
        XCTAssertEqual(hidden.idleLeftWingWidth, wing)
        XCTAssertEqual(hidden.idleRightWingWidth, 0)
        XCTAssertFalse(hidden.shouldHideIdleForMenuOverlap)
        XCTAssertEqual(hidden.frame(isExpanded: false, isIdle: true).maxX, rightX)
    }

    func testCapsuleHidesWhenMenusReachTheCenter() {
        let leftX = 960 - center / 2
        let rightX = 960 + center / 2

        let leftBlocked = geometry(ScreenFixtures.macMini1080p, context: .init(appMenuRightEdgeX: leftX))
        XCTAssertTrue(leftBlocked.suppressesIdleCapsule)
        XCTAssertTrue(leftBlocked.shouldHideIdleForMenuOverlap)

        let rightBlocked = geometry(ScreenFixtures.macMini1080p, context: .init(statusItemsLeftEdgeX: rightX))
        XCTAssertTrue(rightBlocked.shouldHideIdleForMenuOverlap)

        // Hover to expand still works when the idle capsule is hidden.
        XCTAssertTrue(rightBlocked.allowsAutomaticPresentation)
    }

    func testCapsuleIgnoresMenusWhenAvoidMenuOverlapIsOff() {
        let options = NotchGeometry.Options(avoidMenuOverlap: false)
        let geometry = geometry(
            ScreenFixtures.macMini1080p,
            options: options,
            context: .init(appMenuRightEdgeX: 1_000, statusItemsLeftEdgeX: 900)
        )
        XCTAssertEqual(geometry.idleLeftWingWidth, wing)
        XCTAssertEqual(geometry.idleRightWingWidth, wing)
        XCTAssertFalse(geometry.shouldHideIdleForMenuOverlap)
    }

    func testCapsuleHidesWithAutoHiddenMenuBarOrFullScreen() {
        let autoHidden = geometry(ScreenFixtures.macMini1080pAutoHiddenMenuBar)
        XCTAssertTrue(autoHidden.shouldHideIdleForMenuOverlap)
        XCTAssertEqual(autoHidden.idleSize.height, NotchFlowConstants.fallbackMenuBarHeight)
        XCTAssertEqual(autoHidden.hoverTriggerRect.maxY, 1080)

        let fullScreen = geometry(ScreenFixtures.macMini1080p, context: .init(isFullScreenActive: true))
        XCTAssertTrue(fullScreen.shouldHideIdleForMenuOverlap)
        XCTAssertTrue(fullScreen.allowsAutomaticPresentation)
    }

    func testTopCenterCapsuleStaysVisibleWithoutALiveActivity() {
        XCTAssertTrue(geometry(ScreenFixtures.macMini1080p).showsCapsuleWhileIdle)
        XCTAssertTrue(geometry(ScreenFixtures.externalDisplay).showsCapsuleWhileIdle)

        // Not for the other placements, hidden menu bars, full screen, or a hardware notch.
        XCTAssertFalse(geometry(ScreenFixtures.macMini1080p, options: .init(nonNotchPlacement: .hoverOnly)).showsCapsuleWhileIdle)
        XCTAssertFalse(geometry(ScreenFixtures.macMini1080p, options: .init(nonNotchPlacement: .off)).showsCapsuleWhileIdle)
        XCTAssertFalse(geometry(ScreenFixtures.macMini1080pAutoHiddenMenuBar).showsCapsuleWhileIdle)
        XCTAssertFalse(geometry(ScreenFixtures.macMini1080p, context: .init(isFullScreenActive: true)).showsCapsuleWhileIdle)
        XCTAssertFalse(geometry(ScreenFixtures.macBookPro14).showsCapsuleWhileIdle)
    }

    func testPlacementOffDisablesAutomaticPresentation() {
        let geometry = geometry(ScreenFixtures.macMini1080p, options: .init(nonNotchPlacement: .off))
        XCTAssertFalse(geometry.allowsAutomaticPresentation)
        // The menu bar icon can still open the island at the usual place.
        XCTAssertEqual(geometry.frame(isExpanded: true).midX, 960)
    }

    func testCapsuleSpanCoversWingsAndMargin() {
        let span = NotchGeometry.menuBarCapsuleSpan(for: ScreenFixtures.macMini1080p)
        let reach = wing + NotchFlowConstants.menuOverlapMargin
        XCTAssertEqual(span, (960 - center / 2 - reach)...(960 + center / 2 + reach))
        XCTAssertNil(NotchGeometry.menuBarCapsuleSpan(for: ScreenFixtures.reservedBandWithoutAuxiliaryAreas))
    }

    // MARK: Notification drop banner

    /// The panel frame and the banner view share one height, so no transparent strip is left.
    func testDropBannerFrameMatchesBannerHeightOnEveryAnchor() {
        let cases: [(ScreenMetrics, topInset: CGFloat)] = [
            (ScreenFixtures.macBookPro14, 32),          // notch: unchanged layout
            (ScreenFixtures.macBookPro16, 32),
            (ScreenFixtures.macMini1080p, 24),          // capsule: content starts below the menu bar
            (ScreenFixtures.externalDisplay, 24),
            (ScreenFixtures.dynamicIsland, 0),          // already hangs below the system band
        ]
        for (metrics, topInset) in cases {
            let geometry = geometry(metrics)
            XCTAssertEqual(geometry.dropBannerTopInset, topInset, metrics.identifier)
            XCTAssertEqual(geometry.dropBannerHeight, NotchFlowConstants.dropBannerHeight(topInset: topInset), metrics.identifier)
            let frame = geometry.frame(isExpanded: false, isIdle: true, idleBannerWidth: 300)
            XCTAssertEqual(frame.height, geometry.dropBannerHeight, metrics.identifier)
            XCTAssertEqual(frame.maxY, geometry.islandTopY, metrics.identifier)
        }
        // Notched MacBooks keep their 84 pt banner.
        XCTAssertEqual(geometry(ScreenFixtures.macBookPro14).dropBannerHeight, 84)
    }

    // MARK: Simulated no-notch

    func testSimulatedNoNotchTreatsNotchedMacBookAsCapsule() {
        let simulated = ScreenFixtures.macBookPro14.withoutTopCutout()
        XCTAssertEqual(NotchGeometry.classifyTopCutout(simulated), TopCutout.none)

        let geometry = geometry(simulated)
        XCTAssertEqual(geometry.anchor, .menuBarCapsule)
        // The notched MacBook's menu bar is 33 pt tall; the capsule follows it.
        XCTAssertEqual(geometry.idleSize.height, 33)
        XCTAssertEqual(geometry.frame(isExpanded: false, isIdle: true).midX, 756)
    }

    // MARK: Dynamic Island and other system cutouts

    func testNarrowGapIsTreatedAsSystemIsland() {
        let metrics = ScreenFixtures.dynamicIsland
        XCTAssertEqual(
            NotchGeometry.classifyTopCutout(metrics),
            .systemIsland(gap: CGRect(x: 700, y: 950, width: 112, height: 32))
        )
        XCTAssertEqual(geometry(metrics).anchor, .besideSystemIsland)
    }

    /// "Larger Text" and other scaled modes shrink the notch in points (to ~125 pt at 1024 pt);
    /// it must still be wrapped, not left uncovered as a system island.
    func testNotchIsRecognizedAtEveryScaledResolution() {
        for mode in ScreenFixtures.scaledNotchedModes {
            // Both notch shares, so every mode is covered at the narrowest plausible notch.
            for ratio in [mode.ratio, ScreenFixtures.notchWidthRatio16] {
                let metrics = ScreenFixtures.scaledNotched(width: mode.width, height: mode.height, ratio: ratio)
                guard case .hardwareNotch = NotchGeometry.classifyTopCutout(metrics) else {
                    XCTFail("\(mode.model) at \(Int(mode.width))×\(Int(mode.height)) (ratio \(ratio)) is not a notch")
                    continue
                }
                XCTAssertEqual(geometry(metrics).anchor, .hardwareNotch)
            }
        }
    }

    func testDynamicIslandStaysASystemIslandAtScaledResolutions() {
        let islandRatio: CGFloat = 112 / 1512
        for mode in ScreenFixtures.scaledNotchedModes {
            let metrics = ScreenFixtures.scaledNotched(width: mode.width, height: mode.height, ratio: islandRatio)
            guard case .systemIsland(let gap?) = NotchGeometry.classifyTopCutout(metrics) else {
                XCTFail("\(mode.model) at \(Int(mode.width)) pt should keep its system island")
                continue
            }
            XCTAssertEqual(gap.width, (mode.width * islandRatio).rounded())
        }
    }

    func testOffCenterGapIsNotTreatedAsNotch() {
        var metrics = ScreenFixtures.macBookPro14
        metrics.auxiliaryTopLeftArea = CGRect(x: 0, y: 950, width: 900, height: 32)
        metrics.auxiliaryTopRightArea = CGRect(x: 1085, y: 950, width: 427, height: 32)
        guard case .systemIsland(let gap?) = NotchGeometry.classifyTopCutout(metrics) else {
            return XCTFail("off-center gap should be a system island")
        }
        XCTAssertEqual(gap.width, 185)
    }

    func testOverlappingAuxiliaryAreasAreNotANotch() {
        var metrics = ScreenFixtures.macBookPro14
        metrics.auxiliaryTopLeftArea = CGRect(x: 0, y: 950, width: 800, height: 32)
        metrics.auxiliaryTopRightArea = CGRect(x: 700, y: 950, width: 812, height: 32)
        XCTAssertEqual(NotchGeometry.classifyTopCutout(metrics), .systemIsland(gap: nil))
    }

    func testWingsSitBesideDynamicIslandWithoutCoveringIt() {
        let metrics = ScreenFixtures.dynamicIsland
        let gap = CGRect(x: 700, y: 950, width: 112, height: 32)
        let geometry = geometry(metrics)

        XCTAssertFalse(geometry.hasPhysicalNotch)
        XCTAssertFalse(geometry.fillsIdleCenter, "the system island must stay uncovered")

        let idle = geometry.frame(isExpanded: false, isIdle: true)
        XCTAssertEqual(idle.maxY, 982)
        XCTAssertEqual(idle.height, 32)
        XCTAssertEqual(idle.midX, gap.midX)

        // Painted wing slots end before the island starts and begin after it ends.
        let layout = geometry.idleWingLayout()
        XCTAssertLessThanOrEqual(idle.minX + layout.leftSlotWidth, gap.minX)
        XCTAssertGreaterThanOrEqual(idle.maxX - layout.rightSlotWidth, gap.maxX)

        // Hover the island area itself, like a notch.
        XCTAssertTrue(geometry.hoverTriggerRect.contains(CGPoint(x: gap.midX, y: gap.midY)))
    }

    func testExpandedIslandHangsBelowDynamicIsland() {
        let geometry = geometry(ScreenFixtures.dynamicIsland)
        let gap = CGRect(x: 700, y: 950, width: 112, height: 32)

        let expanded = geometry.frame(isExpanded: true)
        XCTAssertEqual(expanded.maxY, 950)
        XCTAssertLessThanOrEqual(expanded.maxY, gap.minY)
        XCTAssertEqual(expanded.midX, gap.midX)
        XCTAssertEqual(geometry.contentTopInset, 0)

        let banner = geometry.frame(isExpanded: false, isIdle: true, idleBannerWidth: 300)
        XCTAssertLessThanOrEqual(banner.maxY, gap.minY)
    }

    func testDynamicIslandWingsAvoidMenus() {
        let geometry = geometry(
            ScreenFixtures.dynamicIsland,
            context: .init(appMenuRightEdgeX: 650, statusItemsLeftEdgeX: 860)
        )
        XCTAssertEqual(geometry.idleLeftWingWidth, 0)
        XCTAssertEqual(geometry.idleRightWingWidth, 0)
        XCTAssertTrue(geometry.shouldHideIdleForMenuOverlap)
    }

    func testUnknownSystemCutoutHangsEverythingBelowReservedBand() {
        let metrics = ScreenFixtures.reservedBandWithoutAuxiliaryAreas
        XCTAssertEqual(NotchGeometry.classifyTopCutout(metrics), .systemIsland(gap: nil))

        let geometry = geometry(metrics)
        XCTAssertEqual(geometry.anchor, .belowSystemIsland)
        XCTAssertTrue(geometry.fillsIdleCenter)

        let idle = geometry.frame(isExpanded: false, isIdle: true)
        XCTAssertEqual(idle.maxY, 950)
        XCTAssertEqual(idle.midX, 756)
        XCTAssertEqual(geometry.frame(isExpanded: true).maxY, 950)

        // Hovering the top band or the capsule below it both count.
        XCTAssertTrue(geometry.hoverTriggerRect.contains(CGPoint(x: 756, y: 975)))
        XCTAssertTrue(geometry.hoverTriggerRect.contains(CGPoint(x: 756, y: 930)))
    }
}
