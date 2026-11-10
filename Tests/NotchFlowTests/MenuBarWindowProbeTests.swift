import CoreGraphics
import XCTest
@testable import NotchFlow

final class MenuBarWindowProbeTests: XCTestCase {
    private let level = 24
    private let primaryMaxY: CGFloat = 982
    /// An external display to the right of a 1512×982 MacBook, top-aligned 98 pt higher.
    private let external = CGRect(x: 1512, y: -98, width: 1920, height: 1080)

    private func window(owner: String = "Window Server", layer: Int = 24, _ rect: CGRect) -> [String: Any] {
        [
            kCGWindowOwnerName as String: owner,
            kCGWindowLayer as String: layer,
            kCGWindowBounds as String: rect.dictionaryRepresentation as NSDictionary,
        ]
    }

    func testFindsTheMenuBarDrawnOnTheDisplay() {
        let windows = [
            window(CGRect(x: 0, y: 0, width: 1512, height: 33)),
            window(CGRect(x: 1512, y: 0, width: 1920, height: 30)),
        ]
        XCTAssertEqual(
            MenuBarWindowProbe.menuBarHeight(in: windows, screenFrame: external, primaryMaxY: primaryMaxY, menuLevel: level),
            30
        )
    }

    func testIgnoresOtherDisplaysAppsAndLevels() {
        let windows = [
            window(CGRect(x: 0, y: 0, width: 1512, height: 33)),
            window(owner: "Some App", CGRect(x: 1512, y: 0, width: 1920, height: 30)),
            window(layer: 25, CGRect(x: 1512, y: 0, width: 1920, height: 30)),
            window(CGRect(x: 2400, y: 0, width: 200, height: 30)),
        ]
        XCTAssertEqual(
            MenuBarWindowProbe.menuBarHeight(in: windows, screenFrame: external, primaryMaxY: primaryMaxY, menuLevel: level),
            0
        )
    }
}
