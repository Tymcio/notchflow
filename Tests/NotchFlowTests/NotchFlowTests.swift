import XCTest
@testable import NotchFlow

/// Hardware-notch geometry, computed from fixed display fixtures so results do not depend on
/// the Mac running the tests.
@MainActor
final class NotchGeometryTests: XCTestCase {
    private let options = NotchGeometry.Options()
    private let wing = NotchFlowConstants.idleWingProtrusion

    private func geometry(
        _ metrics: ScreenMetrics,
        options: NotchGeometry.Options? = nil,
        appMenuRightEdgeX: CGFloat? = nil
    ) -> NotchGeometry {
        NotchGeometry.make(
            metrics: metrics,
            options: options ?? self.options,
            context: NotchGeometry.MenuBarContext(appMenuRightEdgeX: appMenuRightEdgeX)
        )
    }

    func testNotchedMacBooksAreClassifiedAsHardwareNotch() {
        for metrics in [ScreenFixtures.macBookPro14, ScreenFixtures.macBookPro16] {
            let leftX = metrics.auxiliaryTopLeftArea!.maxX - NotchFlowConstants.notchWidthOverlapFudge / 2
            XCTAssertEqual(
                NotchGeometry.classifyTopCutout(metrics),
                .hardwareNotch(leftX: leftX, width: ScreenFixtures.notchGapWidth + NotchFlowConstants.notchWidthOverlapFudge),
                metrics.identifier
            )
            let geometry = geometry(metrics)
            XCTAssertEqual(geometry.anchor, .hardwareNotch)
            XCTAssertTrue(geometry.hasPhysicalNotch)
            XCTAssertTrue(geometry.allowsAutomaticPresentation)
            XCTAssertFalse(geometry.fillsIdleCenter)
        }
    }

    /// Guards the notched-MacBook layout against regressions from the notch-less work.
    func testMacBookPro14GeometryMatchesNotchLayout() {
        let geometry = geometry(ScreenFixtures.macBookPro14)

        XCTAssertEqual(geometry.notchLeftX, 661.5)
        XCTAssertEqual(geometry.physicalNotchCutoutWidth, 189)
        XCTAssertEqual(geometry.notchTopInset, 32)
        XCTAssertEqual(geometry.contentTopInset, 32)
        XCTAssertEqual(geometry.hoverTriggerRect, CGRect(x: 661.5, y: 950, width: 189, height: 32))
        XCTAssertEqual(geometry.idleSize, CGSize(width: 297, height: 32))
        XCTAssertEqual(geometry.expandedSize, CGSize(width: 569, height: 218))
        XCTAssertEqual(geometry.frame(isExpanded: false, isIdle: true), CGRect(x: 608, y: 950, width: 297, height: 32))
        XCTAssertEqual(geometry.frame(isExpanded: true), CGRect(x: 472, y: 764, width: 569, height: 218))
        XCTAssertEqual(
            geometry.hoverProximityRect(forExit: false),
            CGRect(x: 653.5, y: 926, width: 205, height: 80)
        )
    }

    func testMacBookPro16GeometryCentersOnNotch() {
        let geometry = geometry(ScreenFixtures.macBookPro16)
        let notchCenter = geometry.notchLeftX! + geometry.physicalNotchCutoutWidth / 2

        XCTAssertEqual(notchCenter, 864)
        XCTAssertEqual(geometry.frame(isExpanded: true).midX, notchCenter, accuracy: 0.5)
        XCTAssertEqual(geometry.frame(isExpanded: false, isIdle: true).maxY, 1117)
        XCTAssertEqual(geometry.hoverTriggerRect.minY, 1117 - 32)
    }

    func testExpandedWidthHonorsPremiumWidthAndTabBarMinimum() {
        let premium = NotchGeometry.Options(isPremiumEnabled: true, customIslandWidth: 10_000)
        XCTAssertEqual(geometry(ScreenFixtures.macBookPro14, options: premium).expandedSize.width, 569)

        let minimumWidth = max(
            NotchFlowConstants.defaultExpandedWidth,
            189 + wing * 2,
            NotchGeometry.minimumExpandedWidthForTabBar(cutoutWidth: 189)
        ).rounded()
        XCTAssertEqual(geometry(ScreenFixtures.macBookPro14).expandedSize.width, minimumWidth)
    }

    func testIdleLeftWingHidesWhenMenuUnderFullWing() {
        let notchLeftX: CGFloat = 700

        XCTAssertEqual(
            NotchGeometry.idleLeftWingWidth(defaultWing: wing, notchLeftX: notchLeftX, appMenuRightEdgeX: nil),
            wing
        )

        // Enough room for the full wing (700 - 640 - margin >= 54): keep it.
        let fits = NotchGeometry.idleLeftWingWidth(
            defaultWing: wing,
            notchLeftX: notchLeftX,
            appMenuRightEdgeX: 640
        )
        XCTAssertEqual(fits, wing)

        // Menu would sit under the wing: hide it entirely, no partial width.
        let hidden = NotchGeometry.idleLeftWingWidth(
            defaultWing: wing,
            notchLeftX: notchLeftX,
            appMenuRightEdgeX: 650
        )
        XCTAssertEqual(hidden, 0)
    }

    func testIdleWingWidthsFullWhenAvoidMenuOverlapWithoutAXData() {
        let wings = NotchGeometry.idleWingWidths(
            avoidMenuOverlap: true,
            defaultWing: wing,
            notchLeftX: 700,
            hasNotch: true,
            appMenuRightEdgeX: nil
        )
        XCTAssertEqual(wings.left, wing)
        XCTAssertEqual(wings.right, wing)
    }

    func testIdleWingWidthsHideLeftWhenMenuEdgeTooClose() {
        let wings = NotchGeometry.idleWingWidths(
            avoidMenuOverlap: true,
            defaultWing: wing,
            notchLeftX: 700,
            hasNotch: true,
            appMenuRightEdgeX: 650
        )
        XCTAssertEqual(wings.left, 0)
        XCTAssertEqual(wings.right, wing)

        let ignored = NotchGeometry.idleWingWidths(
            avoidMenuOverlap: false,
            defaultWing: wing,
            notchLeftX: 700,
            hasNotch: true,
            appMenuRightEdgeX: 650
        )
        XCTAssertEqual(ignored.left, wing)
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
        let metrics = ScreenFixtures.macBookPro14
        let notchLeftX = metrics.auxiliaryTopLeftArea!.maxX - NotchFlowConstants.notchWidthOverlapFudge / 2
        // The full wing needs notchLeftX - edge - margin >= wing, i.e. edge <= 601.5 here.
        let fullWingEdge = notchLeftX - NotchFlowConstants.menuOverlapMargin - wing - 10
        let hiddenWingEdge = notchLeftX - NotchFlowConstants.menuOverlapMargin - wing + 10

        let full = geometry(metrics, appMenuRightEdgeX: fullWingEdge)
        let hiddenLeft = geometry(metrics, appMenuRightEdgeX: hiddenWingEdge)

        XCTAssertGreaterThan(full.idleLeftWingWidth, 0)
        XCTAssertEqual(hiddenLeft.idleLeftWingWidth, 0)

        let fullFrame = full.frame(isExpanded: false, isIdle: true)
        let hiddenLeftFrame = hiddenLeft.frame(isExpanded: false, isIdle: true)

        XCTAssertEqual(fullFrame.minX, (notchLeftX - wing).rounded(.toNearestOrAwayFromZero))
        XCTAssertEqual(hiddenLeftFrame.minX, fullFrame.minX)
        XCTAssertEqual(hiddenLeftFrame.width, fullFrame.width)
        XCTAssertEqual(
            hiddenLeftFrame.width,
            hiddenLeft.physicalNotchCutoutWidth + wing + hiddenLeft.idleRightWingWidth
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
        let geometry = geometry(ScreenFixtures.macBookPro14, appMenuRightEdgeX: 10_000)
        XCTAssertEqual(geometry.idleLeftWingWidth, 0)
        XCTAssertGreaterThan(geometry.idleRightWingWidth, 0)
        XCTAssertFalse(geometry.shouldHideIdleForMenuOverlap)
    }

    func testNotchIgnoresNonNotchPlacementAndCapsuleContext() {
        let off = NotchGeometry.Options(nonNotchPlacement: .off)
        let context = NotchGeometry.MenuBarContext(statusItemsLeftEdgeX: 700, isFullScreenActive: true)
        let geometry = NotchGeometry.make(metrics: ScreenFixtures.macBookPro14, options: off, context: context)

        XCTAssertEqual(geometry, self.geometry(ScreenFixtures.macBookPro14))
        XCTAssertTrue(geometry.allowsAutomaticPresentation)
        XCTAssertFalse(geometry.suppressesIdleCapsule)
        XCTAssertNil(NotchGeometry.menuBarCapsuleSpan(for: ScreenFixtures.macBookPro14))
    }

    func testWithExpandedHeightKeepsEverythingElse() {
        let geometry = geometry(ScreenFixtures.macBookPro14)
        let taller = geometry.withExpandedHeight(400.4)
        XCTAssertEqual(taller.expandedSize, CGSize(width: geometry.expandedSize.width, height: 400))
        XCTAssertEqual(taller.withExpandedHeight(geometry.expandedSize.height), geometry)
    }
}

final class LicenseStatusTests: XCTestCase {
    func testPremiumTiers() {
        XCTAssertFalse(LicenseStatus.free.isPremium)
        XCTAssertTrue(LicenseStatus(tier: .lifetime, key: "x", validatedAt: .now, expiresAt: nil, hasAgentsAddon: false, agentsKey: nil, agentsValidatedAt: nil).isPremium)
        XCTAssertTrue(LicenseStatus(tier: .annual, key: "x", validatedAt: .now, expiresAt: .now.addingTimeInterval(3600), hasAgentsAddon: false, agentsKey: nil, agentsValidatedAt: nil).isPremium)
    }

    func testAgentsAddonFlag() {
        let status = LicenseStatus(
            tier: .free,
            key: nil,
            validatedAt: nil,
            expiresAt: nil,
            hasAgentsAddon: true,
            agentsKey: "NOTCHFLOW_AGENTS_x",
            agentsValidatedAt: .now
        )
        XCTAssertFalse(status.isPremium)
        XCTAssertTrue(status.hasAgentsAddon)
    }

    func testAgentsKeyDetection() {
        XCTAssertTrue(PolarLicenseClient.looksLikeAgentsKey("NOTCHFLOW_AGENTS_abc"))
        XCTAssertFalse(PolarLicenseClient.looksLikeAgentsKey("NOTCHFLOW_LIFETIME_abc"))
    }

    @MainActor
    func testAgentPermissionIngest() {
        let manager = AgentSessionManager()
        manager.ingestEvent([
            "agent": "claude",
            "event": "permission",
            "sessionId": "s1",
            "title": "fix auth",
            "toolName": "Bash",
            "summary": "npm test",
            "permissionId": "p1",
        ])
        XCTAssertEqual(manager.sessions.count, 1)
        XCTAssertEqual(manager.sessions[0].phase, .waitingPermission)
        manager.decidePermission(id: "p1", decision: .allow)
        XCTAssertEqual(manager.permissionDecision(id: "p1"), .allow)
        XCTAssertEqual(manager.sessions[0].phase, .running)
    }
}

import AppKit
