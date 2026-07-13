import SwiftUI

enum IslandStyle {
    static let primaryText = Color.white.opacity(0.95)
    static let secondaryText = Color.white.opacity(0.55)
    static let tertiaryText = Color.white.opacity(0.45)
    static let accentText = Color.white.opacity(0.82)
    static let surfaceFill = NotchFlowBrand.graphite.opacity(0.72)
    static let surfaceStroke = Color.white.opacity(0.08)
}

enum IslandRadius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 14
}

enum IslandMotion {
    static let quick = Animation.easeOut(duration: 0.2)
}
