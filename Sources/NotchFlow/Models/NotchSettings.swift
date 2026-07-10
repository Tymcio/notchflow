import Foundation
import SwiftUI

@Observable
@MainActor
final class NotchSettings {
    static let shared = NotchSettings()

    var launchAtLogin: Bool {
        didSet { UserDefaults.standard.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }

    var customIslandWidth: CGFloat {
        didSet { UserDefaults.standard.set(customIslandWidth, forKey: Keys.customIslandWidth) }
    }

    var customIslandHeight: CGFloat {
        didSet { UserDefaults.standard.set(customIslandHeight, forKey: Keys.customIslandHeight) }
    }

    var selectedTheme: IslandTheme {
        didSet { UserDefaults.standard.set(selectedTheme.rawValue, forKey: Keys.selectedTheme) }
    }

    var hiddenAppBundleIDs: [String] {
        didSet { UserDefaults.standard.set(hiddenAppBundleIDs, forKey: Keys.hiddenAppBundleIDs) }
    }

    var clipboardMonitoringEnabled: Bool {
        didSet { UserDefaults.standard.set(clipboardMonitoringEnabled, forKey: Keys.clipboardMonitoringEnabled) }
    }

    var localAPIEnabled: Bool {
        didSet { UserDefaults.standard.set(localAPIEnabled, forKey: Keys.localAPIEnabled) }
    }

    var isPremiumEnabled: Bool = false

    private enum Keys {
        static let launchAtLogin = "launchAtLogin"
        static let customIslandWidth = "customIslandWidth"
        static let customIslandHeight = "customIslandHeight"
        static let selectedTheme = "selectedTheme"
        static let hiddenAppBundleIDs = "hiddenAppBundleIDs"
        static let clipboardMonitoringEnabled = "clipboardMonitoringEnabled"
        static let localAPIEnabled = "localAPIEnabled"
    }

    private init() {
        let defaults = UserDefaults.standard
        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        customIslandWidth = defaults.object(forKey: Keys.customIslandWidth) as? CGFloat ?? 340
        customIslandHeight = defaults.object(forKey: Keys.customIslandHeight) as? CGFloat ?? 148
        let themeRaw = defaults.string(forKey: Keys.selectedTheme) ?? IslandTheme.system.rawValue
        selectedTheme = IslandTheme(rawValue: themeRaw) ?? .system
        hiddenAppBundleIDs = defaults.stringArray(forKey: Keys.hiddenAppBundleIDs) ?? []
        clipboardMonitoringEnabled = defaults.bool(forKey: Keys.clipboardMonitoringEnabled)
        localAPIEnabled = defaults.object(forKey: Keys.localAPIEnabled) as? Bool ?? true
    }
}

enum IslandTheme: String, CaseIterable, Identifiable, Sendable {
    case system
    case midnight
    case aurora
    case ember

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Systemowy"
        case .midnight: "Północ"
        case .aurora: "Zorza"
        case .ember: "Żar"
        }
    }

    var accent: Color {
        switch self {
        case .system: .accentColor
        case .midnight: Color(red: 0.35, green: 0.45, blue: 0.95)
        case .aurora: Color(red: 0.2, green: 0.85, blue: 0.7)
        case .ember: Color(red: 0.95, green: 0.45, blue: 0.25)
        }
    }
}
