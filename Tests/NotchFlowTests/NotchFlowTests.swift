import XCTest
@testable import NotchFlow

@MainActor
final class NotchGeometryTests: XCTestCase {
    func testVirtualCapsuleDefaultsWhenNoNotch() {
        let settings = NotchSettings.shared
        if let screen = NSScreen.main {
            let geometry = NotchGeometry.make(for: screen, settings: settings)
            XCTAssertGreaterThan(geometry.expandedSize.width, 0)
            XCTAssertGreaterThan(geometry.expandedSize.height, 0)
            XCTAssertLessThanOrEqual(geometry.expandedSize.width, NotchFlowConstants.maxExpandedWidth)
        }
    }

    func testIdleLeftWingHidesWhenMenuUnderFullWing() {
        let defaultWing = NotchFlowConstants.idleWingProtrusion
        let notchLeftX: CGFloat = 700

        XCTAssertEqual(
            NotchGeometry.idleLeftWingWidth(defaultWing: defaultWing, notchLeftX: notchLeftX, appMenuRightEdgeX: nil),
            defaultWing
        )

        // Enough room for the full wing (700 - 640 - margin >= 54): keep it.
        let fits = NotchGeometry.idleLeftWingWidth(
            defaultWing: defaultWing,
            notchLeftX: notchLeftX,
            appMenuRightEdgeX: 640
        )
        XCTAssertEqual(fits, defaultWing)

        // Menu would sit under the wing: hide it entirely, no partial width.
        let hidden = NotchGeometry.idleLeftWingWidth(
            defaultWing: defaultWing,
            notchLeftX: notchLeftX,
            appMenuRightEdgeX: 650
        )
        XCTAssertEqual(hidden, 0)
    }

    func testIdleWingWidthsFullWhenAvoidMenuOverlapWithoutAXData() {
        let settings = NotchSettings.shared
        let previous = settings.avoidMenuOverlap
        settings.avoidMenuOverlap = true
        defer { settings.avoidMenuOverlap = previous }

        let wings = NotchGeometry.idleWingWidths(
            settings: settings,
            defaultWing: NotchFlowConstants.idleWingProtrusion,
            notchLeftX: 700,
            hasNotch: true,
            appMenuRightEdgeX: nil
        )
        XCTAssertEqual(wings.left, NotchFlowConstants.idleWingProtrusion)
        XCTAssertEqual(wings.right, NotchFlowConstants.idleWingProtrusion)
    }

    func testIdleWingWidthsHideLeftWhenMenuEdgeTooClose() {
        let settings = NotchSettings.shared
        let previous = settings.avoidMenuOverlap
        settings.avoidMenuOverlap = true
        defer { settings.avoidMenuOverlap = previous }

        let wings = NotchGeometry.idleWingWidths(
            settings: settings,
            defaultWing: NotchFlowConstants.idleWingProtrusion,
            notchLeftX: 700,
            hasNotch: true,
            appMenuRightEdgeX: 650
        )
        XCTAssertEqual(wings.left, 0)
        XCTAssertEqual(wings.right, NotchFlowConstants.idleWingProtrusion)
    }

    func testMinimumExpandedWidthFitsTabBarAroundNotch() {
        let minimum = NotchGeometry.minimumExpandedWidthForTabBar(cutoutWidth: 184)
        XCTAssertGreaterThanOrEqual(minimum, 420)

        let leading = CGFloat(IslandModule.leadingTabs.count) * NotchFlowConstants.expandedTabSlotWidth
        let trailing = CGFloat(IslandModule.trailingTabs.count) * NotchFlowConstants.expandedTabSlotWidth
        let innerWidth = minimum - 20
        let spacer = innerWidth - leading - trailing
        let notchRight = (minimum + 184) / 2
        XCTAssertGreaterThanOrEqual(10 + leading + spacer, notchRight)
    }

    func testIdleFrameKeepsNotchAlignedWhenLeftWingHidden() {
        let settings = NotchSettings.shared
        guard let screen = NSScreen.main,
              screen.safeAreaInsets.top > 0,
              let notchLeftX = screen.auxiliaryTopLeftArea.map({ $0.maxX - NotchFlowConstants.notchWidthOverlapFudge / 2 }) else {
            return
        }

        let full = NotchGeometry.make(for: screen, settings: settings, appMenuRightEdgeX: 640)
        let hiddenLeft = NotchGeometry.make(for: screen, settings: settings, appMenuRightEdgeX: 650)

        XCTAssertGreaterThan(full.idleLeftWingWidth, 0)
        XCTAssertEqual(hiddenLeft.idleLeftWingWidth, 0)

        let fullFrame = full.frame(isExpanded: false, isIdle: true)
        let hiddenLeftFrame = hiddenLeft.frame(isExpanded: false, isIdle: true)

        XCTAssertEqual(fullFrame.minX, notchLeftX - NotchFlowConstants.idleWingProtrusion)
        XCTAssertEqual(hiddenLeftFrame.minX, fullFrame.minX)
        XCTAssertEqual(hiddenLeftFrame.width, fullFrame.width)
        XCTAssertEqual(
            hiddenLeftFrame.width,
            hiddenLeft.physicalNotchCutoutWidth + NotchFlowConstants.idleWingProtrusion + hiddenLeft.idleRightWingWidth
        )

        let fullLayout = full.idleWingLayout()
        let hiddenLayout = hiddenLeft.idleWingLayout()
        XCTAssertEqual(fullLayout.leftSlotWidth, hiddenLayout.leftSlotWidth)
        XCTAssertEqual(fullLayout.centerClearWidth, hiddenLayout.centerClearWidth)
        XCTAssertEqual(fullLayout.rightSlotWidth, hiddenLayout.rightSlotWidth)
        XCTAssertEqual(fullLayout.panelWidth, hiddenLayout.panelWidth)
        XCTAssertEqual(fullLayout.panelHeight, hiddenLayout.panelHeight)
        XCTAssertLessThanOrEqual(fullLayout.panelHeight, full.notchTopInset)
        XCTAssertEqual(hiddenLayout.visibleLeftWidth, 0)
    }

    func testShouldHideIdleOnlyWhenBothWingsUnavailable() {
        let settings = NotchSettings.shared
        guard let screen = NSScreen.main, screen.safeAreaInsets.top > 0 else { return }

        let geometry = NotchGeometry.make(for: screen, settings: settings, appMenuRightEdgeX: 10_000)
        XCTAssertEqual(geometry.idleLeftWingWidth, 0)
        XCTAssertGreaterThan(geometry.idleRightWingWidth, 0)
        XCTAssertFalse(geometry.shouldHideIdleForMenuOverlap)
    }
}

final class LicenseStatusTests: XCTestCase {
    func testPremiumTiers() {
        XCTAssertFalse(LicenseStatus.free.isPremium)
        XCTAssertTrue(LicenseStatus(tier: .lifetime, key: "x", validatedAt: .now, expiresAt: nil).isPremium)
        XCTAssertTrue(LicenseStatus(tier: .annual, key: "x", validatedAt: .now, expiresAt: .now.addingTimeInterval(3600)).isPremium)
    }
}

import AppKit
