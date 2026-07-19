import SwiftUI

enum IslandStyle {
    static let primaryText = Color.white.opacity(0.95)
    static let secondaryText = Color.white.opacity(0.55)
    static let tertiaryText = Color.white.opacity(0.45)
    static let accentText = Color.white.opacity(0.82)
    /// Outer island / wing / banner fill — same black as the hardware notch.
    static let islandFill = NotchFlowBrand.spaceBlack
    static let surfaceFill = Color.black
    /// Near-invisible edge so chrome does not outline against the notch.
    static let surfaceStroke = Color.white.opacity(0.03)
}

enum IslandRadius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 14
}

enum IslandMotion {
    static let quick = Animation.easeOut(duration: 0.2)
}
