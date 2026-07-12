import Foundation

enum NotchFlowConstants {
    static let appName = "NotchFlow"
    static let bundleID = "eu.notchflow.app"
    static let websiteURL = URL(string: "https://notchflow.eu")!
    static let githubURL = URL(string: "https://github.com/Tymcio/notchflow")!
    static let licenseGraceDays = 14
    static let defaultCollapsedWidth: CGFloat = 200
    static let defaultCollapsedHeight: CGFloat = 40
    static let defaultExpandedWidth: CGFloat = 400
    static let maxExpandedWidth: CGFloat = 440
    static let defaultExpandedContentHeight: CGFloat = 178
    static let expandedVerticalPadding: CGFloat = 12
    static let defaultExpandedHeight: CGFloat = 218
    static let virtualCapsuleWidth: CGFloat = 200
    static let virtualCapsuleHeight: CGFloat = 36
    static let hoverTriggerWidth: CGFloat = 200
    static let hoverExpandThreshold: CGFloat = 32
    /// Slight horizontal forgiveness when aiming at the physical notch cutout.
    static let hoverNotchHorizontalExpand: CGFloat = 8
    /// Hover must linger in the notch band before expanding, so quick clicks reach the app below.
    static let hoverExpandDwellMilliseconds = 220
    /// Extra width beyond expanded island when detecting file drags.
    static let dragDropZoneHorizontalPadding: CGFloat = 40
    /// Extra height below expanded island for file drop targeting.
    static let dragDropZoneVerticalPadding: CGFloat = 24
    /// Approximate width of one expanded tab button incl. padding.
    static let expandedTabSlotWidth: CGFloat = 36
    static let idleWingProtrusion: CGFloat = 54
    static let idleWingInnerOverlap: CGFloat = 12
    static let notchWidthOverlapFudge: CGFloat = 4
    static let idleBottomBleed: CGFloat = 1
    static let defaultNotchCutoutWidth: CGFloat = 184
    /// Space to leave on the right of the notch for menu bar status items (incl. our own icon).
    static let menuBarStatusItemReserve: CGFloat = 96
    /// Gap between the app menu and the idle island left wing.
    static let menuOverlapMargin: CGFloat = 6
    /// Tolerance when deciding whether a menu item belongs to the left cluster.
    static let menuBarItemClusterFudge: CGFloat = 8
    /// Minimum left-wing width worth showing album artwork; below this the wing is hidden.
    static let minIdleWingWidthForArtwork: CGFloat = 28
    static let freeNotesLimit = 5
    static let freeClipboardLimit = 5
    static let premiumClipboardLimit = 50
    static let freePinnedShelfLimit = 3
    static let premiumPinnedShelfLimit = 20
    static let freeDroppedShelfLimit = 1
    static let premiumDroppedShelfLimit = 12
    /// Default loopback port for the local Raycast API (stable across restarts).
    static let localAPIPort: UInt16 = 47_821
}
