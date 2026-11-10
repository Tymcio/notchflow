import CoreGraphics
import Foundation

/// Finds the menu bar the window server actually draws on a display.
///
/// `NSScreen.visibleFrame` is the usual signal, but some displays show a menu bar without
/// reserving it there (seen on secondary and virtual displays in macOS 27). The menu bar
/// itself is a window owned by the window server at the main-menu level, so its on-screen
/// bounds tell us whether a menu bar is showing and how tall it is.
enum MenuBarWindowProbe {
    static let windowServerOwnerName = "Window Server"

    /// Height of the menu bar window shown at the top of `screenFrame`, or 0 when there is none
    /// (auto-hidden menu bar, full-screen Space, "Displays have separate Spaces" off).
    /// `screenFrame` uses AppKit coordinates; `primaryMaxY` is the primary display's `frame.maxY`.
    nonisolated static func visibleMenuBarHeight(on screenFrame: CGRect, primaryMaxY: CGFloat) -> CGFloat {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return 0
        }
        return menuBarHeight(
            in: windows,
            screenFrame: screenFrame,
            primaryMaxY: primaryMaxY,
            menuLevel: Int(CGWindowLevelForKey(.mainMenuWindow))
        )
    }

    /// Pure part of `visibleMenuBarHeight`, for tests: picks the window-server window at the
    /// main-menu level that sits flush with the top of the display and spans most of its width.
    nonisolated static func menuBarHeight(
        in windows: [[String: Any]],
        screenFrame: CGRect,
        primaryMaxY: CGFloat,
        menuLevel: Int
    ) -> CGFloat {
        // Window bounds use a top-left origin on the primary display.
        let top = primaryMaxY - screenFrame.maxY
        var best: CGFloat = 0
        for info in windows {
            guard (info[kCGWindowLayer as String] as? Int) == menuLevel,
                  (info[kCGWindowOwnerName as String] as? String) == windowServerOwnerName,
                  let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary) else {
                continue
            }
            guard abs(bounds.minY - top) <= 1,
                  bounds.minX >= screenFrame.minX - 1,
                  bounds.maxX <= screenFrame.maxX + 1,
                  bounds.width >= screenFrame.width * 0.5,
                  bounds.height > 0, bounds.height < 80 else {
                continue
            }
            best = max(best, bounds.height)
        }
        return best
    }
}
