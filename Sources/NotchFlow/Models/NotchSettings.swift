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
        didSet { scheduleDimensionPersist() }
    }

    var customIslandHeight: CGFloat {
        didSet { scheduleDimensionPersist() }
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

    var avoidMenuOverlap: Bool {
        didSet {
            UserDefaults.standard.set(avoidMenuOverlap, forKey: Keys.avoidMenuOverlap)
            onAvoidMenuOverlapChange?()
        }
    }

    var urlSchemeAutomationEnabled: Bool {
        didSet { UserDefaults.standard.set(urlSchemeAutomationEnabled, forKey: Keys.urlSchemeAutomationEnabled) }
    }

    var lyricsSharingEnabled: Bool {
        didSet { UserDefaults.standard.set(lyricsSharingEnabled, forKey: Keys.lyricsSharingEnabled) }
    }

    var callsInNotchEnabled: Bool {
        didSet { UserDefaults.standard.set(callsInNotchEnabled, forKey: Keys.callsInNotchEnabled) }
    }

    var appNotificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(appNotificationsEnabled, forKey: Keys.appNotificationsEnabled) }
    }

    var allowedNotificationBundleIDs: [String] {
        didSet { UserDefaults.standard.set(allowedNotificationBundleIDs, forKey: Keys.allowedNotificationBundleIDs) }
    }

    var hideNotificationBody: Bool {
        didSet { UserDefaults.standard.set(hideNotificationBody, forKey: Keys.hideNotificationBody) }
    }

    var dismissSystemBanners: Bool {
        didSet { UserDefaults.standard.set(dismissSystemBanners, forKey: Keys.dismissSystemBanners) }
    }

    var isPremiumEnabled: Bool = false {
        didSet {
            guard oldValue != isPremiumEnabled else { return }
            onDimensionsChange?()
        }
    }
    var onAvoidMenuOverlapChange: (() -> Void)?
    var onDimensionsChange: (() -> Void)?

    private var dimensionPersistTask: Task<Void, Never>?

    private enum Keys {
        static let launchAtLogin = "launchAtLogin"
        static let customIslandWidth = "customIslandWidth"
        static let customIslandHeight = "customIslandHeight"
        static let selectedTheme = "selectedTheme"
        static let hiddenAppBundleIDs = "hiddenAppBundleIDs"
        static let clipboardMonitoringEnabled = "clipboardMonitoringEnabled"
        static let localAPIEnabled = "localAPIEnabled"
        static let avoidMenuOverlap = "avoidMenuOverlap"
        static let urlSchemeAutomationEnabled = "urlSchemeAutomationEnabled"
        static let lyricsSharingEnabled = "lyricsSharingEnabled"
        static let callsInNotchEnabled = "callsInNotchEnabled"
        static let appNotificationsEnabled = "appNotificationsEnabled"
        static let allowedNotificationBundleIDs = "allowedNotificationBundleIDs"
        static let hideNotificationBody = "hideNotificationBody"
        static let dismissSystemBanners = "dismissSystemBanners"
    }

    private init() {
        let defaults = UserDefaults.standard
        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        customIslandWidth = defaults.object(forKey: Keys.customIslandWidth) as? CGFloat ?? NotchFlowConstants.defaultExpandedWidth
        let savedHeight = defaults.object(forKey: Keys.customIslandHeight) as? CGFloat
            ?? NotchFlowConstants.defaultExpandedContentHeight
        customIslandHeight = min(
            max(savedHeight, NotchFlowConstants.minimumExpandedContentHeight),
            NotchFlowConstants.maximumExpandedContentHeight
        )
        let themeRaw = defaults.string(forKey: Keys.selectedTheme) ?? IslandTheme.system.rawValue
        if themeRaw == "ember" {
            selectedTheme = .violet
        } else {
            selectedTheme = IslandTheme(rawValue: themeRaw) ?? .system
        }
        hiddenAppBundleIDs = defaults.stringArray(forKey: Keys.hiddenAppBundleIDs) ?? []
        clipboardMonitoringEnabled = defaults.bool(forKey: Keys.clipboardMonitoringEnabled)
        localAPIEnabled = defaults.object(forKey: Keys.localAPIEnabled) as? Bool ?? false
        avoidMenuOverlap = defaults.object(forKey: Keys.avoidMenuOverlap) as? Bool ?? true
        urlSchemeAutomationEnabled = defaults.bool(forKey: Keys.urlSchemeAutomationEnabled)
        lyricsSharingEnabled = defaults.bool(forKey: Keys.lyricsSharingEnabled)
        callsInNotchEnabled = defaults.bool(forKey: Keys.callsInNotchEnabled)
        appNotificationsEnabled = defaults.bool(forKey: Keys.appNotificationsEnabled)
        allowedNotificationBundleIDs = Self.migratedAllowedNotificationBundleIDs(
            defaults.stringArray(forKey: Keys.allowedNotificationBundleIDs) ?? []
        )
        hideNotificationBody = defaults.bool(forKey: Keys.hideNotificationBody)
        dismissSystemBanners = defaults.bool(forKey: Keys.dismissSystemBanners)
    }

    private func scheduleDimensionPersist() {
        dimensionPersistTask?.cancel()
        dimensionPersistTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            UserDefaults.standard.set(customIslandWidth, forKey: Keys.customIslandWidth)
            UserDefaults.standard.set(customIslandHeight, forKey: Keys.customIslandHeight)
            onDimensionsChange?()
        }
    }

    private static func migratedAllowedNotificationBundleIDs(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for id in ids {
            let canonical = NotificationAppCatalog.canonicalBundleID(for: id)
            guard seen.insert(canonical).inserted else { continue }
            result.append(canonical)
        }
        return result
    }
}

enum IslandTheme: String, CaseIterable, Identifiable, Sendable {
    case system
    case midnight
    case aurora
    case violet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "NotchFlow"
        case .midnight: "Graphite"
        case .aurora: "Aurora"
        case .violet: loc("Violet")
        }
    }

    var accent: Color {
        switch self {
        case .system: NotchFlowBrand.electricBlue
        case .midnight: Color.white.opacity(0.72)
        case .aurora: NotchFlowBrand.aurora
        case .violet: NotchFlowBrand.auroraPurple.opacity(0.85)
        }
    }
}
