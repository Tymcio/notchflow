import SwiftUI

/// NotchFlow brand palette — quiet, premium, Apple-adjacent.
enum NotchFlowBrand {
    static let spaceBlack = Color(red: 17 / 255, green: 17 / 255, blue: 17 / 255)
    static let graphite = Color(red: 38 / 255, green: 38 / 255, blue: 38 / 255)
    static let electricBlue = Color(red: 79 / 255, green: 124 / 255, blue: 255 / 255)
    static let aurora = Color(red: 90 / 255, green: 200 / 255, blue: 250 / 255)
    static let liquidCyan = Color(red: 109 / 255, green: 230 / 255, blue: 255 / 255)
    static let auroraPurple = Color(red: 124 / 255, green: 92 / 255, blue: 255 / 255)

    static let glassGradient = LinearGradient(
        colors: [aurora, electricBlue, auroraPurple],
        startPoint: .leading,
        endPoint: .trailing
    )
}
