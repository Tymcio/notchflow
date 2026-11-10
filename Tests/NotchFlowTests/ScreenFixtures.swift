import CoreGraphics
@testable import NotchFlow

/// Display metrics captured from real hardware (or, for the Dynamic Island, modelled on what
/// macOS reports for a notch) so geometry tests never depend on the Mac running them.
enum ScreenFixtures {
    /// Notch gap reported by MacBook Pro / Air at the default "looks like" resolution.
    static let notchGapWidth: CGFloat = 185

    /// 14" MacBook Pro, default scaling (1512×982), 33 pt menu bar around a 32 pt notch.
    static let macBookPro14 = notched(identifier: "Built-in Retina Display (14\")", width: 1512, height: 982)

    /// 16" MacBook Pro, default scaling (1728×1117).
    static let macBookPro16 = notched(identifier: "Built-in Retina Display (16\")", width: 1728, height: 1117)

    /// 27" 1440p external monitor to the right of a 14" MacBook, 24 pt menu bar, 1× backing.
    static let externalDisplay = ScreenMetrics(
        identifier: "LG QHD",
        frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440),
        visibleFrame: CGRect(x: 1512, y: 0, width: 2560, height: 1416),
        backingScaleFactor: 1
    )

    /// Mac mini driving a single 1080p display.
    static let macMini1080p = ScreenMetrics(
        identifier: "DELL P2419H",
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 0, y: 70, width: 1920, height: 986),
        backingScaleFactor: 1
    )

    /// Same Mac mini display with "Automatically hide and show the menu bar" turned on.
    static let macMini1080pAutoHiddenMenuBar = ScreenMetrics(
        identifier: "DELL P2419H",
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 0, y: 70, width: 1920, height: 1010),
        backingScaleFactor: 1
    )

    /// Hypothetical OLED MacBook Pro with a Dynamic Island: a reserved top band whose auxiliary
    /// areas leave only a narrow (112 pt) gap. Values are modelled, not measured.
    static let dynamicIsland = ScreenMetrics(
        identifier: "Built-in OLED Display",
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949),
        safeAreaTop: 32,
        auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 700, height: 32),
        auxiliaryTopRightArea: CGRect(x: 812, y: 950, width: 700, height: 32),
        backingScaleFactor: 2
    )

    /// A reserved top band with no auxiliary areas at all.
    static let reservedBandWithoutAuxiliaryAreas = ScreenMetrics(
        identifier: "Built-in OLED Display",
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949),
        safeAreaTop: 32,
        backingScaleFactor: 2
    )

    /// Notch share of the display width on the 14" MacBook Pro at its default 1512 pt; the notch
    /// is part of the panel, so this share holds at every scaled ("looks like") resolution.
    static let notchWidthRatio14: CGFloat = notchGapWidth / 1512
    /// Same for the 16" (185 pt at 1728 pt) — the smallest notch share of any MacBook.
    static let notchWidthRatio16: CGFloat = notchGapWidth / 1728

    /// Every "looks like" resolution offered in System Settings → Displays, from "Larger Text"
    /// to "More Space".
    static let scaledNotchedModes: [(model: String, width: CGFloat, height: CGFloat, ratio: CGFloat)] = [
        ("13\" MacBook Air", 1024, 665, notchWidthRatio14),
        ("13\" MacBook Air", 1280, 832, notchWidthRatio14),
        ("13\" MacBook Air", 1470, 956, notchWidthRatio14),
        ("13\" MacBook Air", 1710, 1112, notchWidthRatio14),
        ("14\" MacBook Pro", 1024, 665, notchWidthRatio14),
        ("14\" MacBook Pro", 1147, 745, notchWidthRatio14),
        ("14\" MacBook Pro", 1352, 878, notchWidthRatio14),
        ("14\" MacBook Pro", 1512, 982, notchWidthRatio14),
        ("14\" MacBook Pro", 1800, 1169, notchWidthRatio14),
        ("16\" MacBook Pro", 1168, 755, notchWidthRatio16),
        ("16\" MacBook Pro", 1312, 848, notchWidthRatio16),
        ("16\" MacBook Pro", 1496, 967, notchWidthRatio16),
        ("16\" MacBook Pro", 1728, 1117, notchWidthRatio16),
        ("16\" MacBook Pro", 2056, 1329, notchWidthRatio16),
    ]

    /// A notched built-in display at a scaled resolution, its notch scaled by `ratio`.
    static func scaledNotched(width: CGFloat, height: CGFloat, ratio: CGFloat) -> ScreenMetrics {
        notched(
            identifier: "Built-in Retina Display",
            width: width,
            height: height,
            notchWidth: (width * ratio).rounded()
        )
    }

    static func notched(
        identifier: String,
        width: CGFloat,
        height: CGFloat,
        notchWidth: CGFloat = notchGapWidth
    ) -> ScreenMetrics {
        let safeTop: CGFloat = 32
        let sideWidth = (width - notchWidth) / 2
        return ScreenMetrics(
            identifier: identifier,
            frame: CGRect(x: 0, y: 0, width: width, height: height),
            visibleFrame: CGRect(x: 0, y: 0, width: width, height: height - 33),
            safeAreaTop: safeTop,
            auxiliaryTopLeftArea: CGRect(x: 0, y: height - safeTop, width: sideWidth, height: safeTop),
            auxiliaryTopRightArea: CGRect(x: width - sideWidth, y: height - safeTop, width: sideWidth, height: safeTop),
            backingScaleFactor: 2
        )
    }
}
