import XCTest
@testable import NotchFlow

@MainActor
final class NonNotchPlacementTests: XCTestCase {
    func testNewInstallsGetTheTopCenterCapsule() {
        for notch in [true, false, nil] as [Bool?] {
            XCTAssertEqual(
                NonNotchIslandPlacement.defaultPlacement(isExistingInstall: false, builtInDisplayHasNotch: notch),
                .topCenter
            )
        }
    }

    /// Updating on a notched MacBook must not suddenly show a capsule on the external display.
    func testExistingInstallOnNotchedMacBookKeepsHoverOnly() {
        XCTAssertEqual(
            NonNotchIslandPlacement.defaultPlacement(isExistingInstall: true, builtInDisplayHasNotch: true),
            .hoverOnly
        )
        // Lid closed: the notch cannot be seen, keep the old behaviour.
        XCTAssertEqual(
            NonNotchIslandPlacement.defaultPlacement(isExistingInstall: true, builtInDisplayHasNotch: nil),
            .hoverOnly
        )
    }

    func testExistingInstallWithoutNotchGetsTopCenter() {
        XCTAssertEqual(
            NonNotchIslandPlacement.defaultPlacement(isExistingInstall: true, builtInDisplayHasNotch: false),
            .topCenter
        )
    }

    func testHoverOnlyHidesIdleCapsuleButStillOpensOnHover() {
        let options = NotchGeometry.Options(nonNotchPlacement: .hoverOnly)
        for metrics in [ScreenFixtures.macMini1080p, ScreenFixtures.externalDisplay, ScreenFixtures.dynamicIsland] {
            let geometry = NotchGeometry.make(metrics: metrics, options: options, context: .init())
            XCTAssertTrue(geometry.allowsAutomaticPresentation, metrics.identifier)
            XCTAssertTrue(geometry.shouldHideIdleForMenuOverlap, metrics.identifier)
            XCTAssertFalse(geometry.hoverTriggerRect.isEmpty, metrics.identifier)
        }
    }

    func testHoverOnlyDoesNotChangeTheNotch() {
        let hoverOnly = NotchGeometry.make(
            metrics: ScreenFixtures.macBookPro14,
            options: NotchGeometry.Options(nonNotchPlacement: .hoverOnly),
            context: .init()
        )
        let standard = NotchGeometry.make(metrics: ScreenFixtures.macBookPro14, options: .init(), context: .init())
        XCTAssertEqual(hoverOnly, standard)
        XCTAssertFalse(hoverOnly.shouldHideIdleForMenuOverlap)
    }
}
