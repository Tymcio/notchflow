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
    static let defaultExpandedContentHeight: CGFloat = 148
    static let expandedVerticalPadding: CGFloat = 12
    static let defaultExpandedHeight: CGFloat = 188
    static let virtualCapsuleWidth: CGFloat = 200
    static let virtualCapsuleHeight: CGFloat = 36
    static let hoverTriggerWidth: CGFloat = 200
    static let hoverExpandThreshold: CGFloat = 32
    static let idleBarHeight: CGFloat = 32
    static let idleWingProtrusion: CGFloat = 54
    static let idleWingInnerOverlap: CGFloat = 12
    static let notchWidthOverlapFudge: CGFloat = 4
    static let idleBottomBleed: CGFloat = 1
    static let defaultNotchCutoutWidth: CGFloat = 184
    static let freeNotesLimit = 5
    static let freeClipboardLimit = 5
    static let premiumClipboardLimit = 50
}

enum FeatureGate {
    case free
    case premium

    static func current(isPremium: Bool) -> FeatureGate {
        isPremium ? .premium : .free
    }
}
