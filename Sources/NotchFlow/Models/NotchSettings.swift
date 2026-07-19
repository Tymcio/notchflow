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

    var appNotificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(appNotificationsEnabled, forKey: Keys.appNotificationsEnabled) }
    }

    /// Official installed Mac apps allowed in the notification hub.
    var allowedNativeNotificationBundleIDs: [String] {
        didSet { UserDefaults.standard.set(allowedNativeNotificationBundleIDs, forKey: Keys.allowedNativeNotificationBundleIDs) }
    }

    var hideNotificationBody: Bool {
        didSet { UserDefaults.standard.set(hideNotificationBody, forKey: Keys.hideNotificationBody) }
    }

    var dismissSystemBanners: Bool {
        didSet { UserDefaults.standard.set(dismissSystemBanners, forKey: Keys.dismissSystemBanners) }
    }

    /// System sound name from `/System/Library/Sounds` (without extension). Empty = silent.
    var timerAlertSoundName: String {
        didSet { UserDefaults.standard.set(timerAlertSoundName, forKey: Keys.timerAlertSoundName) }
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
        static let appNotificationsEnabled = "appNotificationsEnabled"
        static let allowedNotificationBundleIDs = "allowedNotificationBundleIDs"
        static let allowedNativeNotificationBundleIDs = "allowedNativeNotificationBundleIDs"
        static let allowedRamboxAggregatorBundleIDs = "allowedRamboxAggregatorBundleIDs"
        static let allowedRamboxServiceBundleIDs = "allowedRamboxServiceBundleIDs"
        static let hideNotificationBody = "hideNotificationBody"
        static let dismissSystemBanners = "dismissSystemBanners"
        static let timerAlertSoundName = "timerAlertSoundName"
        static let ramboxAllowlistMigrated = "notificationAllowlistRamboxRemoved"
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
        appNotificationsEnabled = defaults.bool(forKey: Keys.appNotificationsEnabled)
        allowedNativeNotificationBundleIDs = Self.loadMigratedAllowlist(from: defaults)
        hideNotificationBody = defaults.bool(forKey: Keys.hideNotificationBody)
        // Default ON — notch replaces the corner banner for calls and messaging.
        dismissSystemBanners = defaults.object(forKey: Keys.dismissSystemBanners) as? Bool ?? true
        let savedTimerSound = defaults.string(forKey: Keys.timerAlertSoundName) ?? TimerAlertSound.defaultID
        timerAlertSoundName = TimerAlertSound.migratedID(savedTimerSound)
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

    private static func loadMigratedAllowlist(from defaults: UserDefaults) -> [String] {
        var ids: [String] = []

        if defaults.object(forKey: Keys.allowedNativeNotificationBundleIDs) != nil {
            ids.append(contentsOf: defaults.stringArray(forKey: Keys.allowedNativeNotificationBundleIDs) ?? [])
        } else if let legacy = defaults.stringArray(forKey: Keys.allowedNotificationBundleIDs) {
            ids.append(contentsOf: legacy)
        }

        // One-time: fold previously enabled Rambox *native* service IDs into the single allowlist.
        if !defaults.bool(forKey: Keys.ramboxAllowlistMigrated) {
            let ramboxServices = defaults.stringArray(forKey: Keys.allowedRamboxServiceBundleIDs) ?? []
            ids.append(contentsOf: ramboxServices)
            defaults.set(true, forKey: Keys.ramboxAllowlistMigrated)
            defaults.removeObject(forKey: Keys.allowedRamboxAggregatorBundleIDs)
            defaults.removeObject(forKey: Keys.allowedRamboxServiceBundleIDs)
        }

        return migratedAllowedNotificationBundleIDs(ids)
    }

    nonisolated static func migratedAllowedNotificationBundleIDs(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for id in ids {
            let canonical = NotificationAppCatalog.canonicalBundleID(for: id)
            guard NotificationAppCatalog.isSupportedNotificationApp(canonical) else { continue }
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
