import XCTest
@testable import NotchFlow

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
}

final class LicenseStatusTests: XCTestCase {
    func testPremiumTiers() {
        XCTAssertFalse(LicenseStatus.free.isPremium)
        XCTAssertTrue(LicenseStatus(tier: .lifetime, key: "x", validatedAt: .now, expiresAt: nil).isPremium)
        XCTAssertTrue(LicenseStatus(tier: .annual, key: "x", validatedAt: .now, expiresAt: .now.addingTimeInterval(3600)).isPremium)
    }
}

import AppKit
