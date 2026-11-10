import AppKit
import Foundation
import IOKit.ps
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

    /// Poll Claude Code / Codex usage APIs using the login already on this Mac.
    var agentUsagePollingEnabled: Bool {
        didSet { UserDefaults.standard.set(agentUsagePollingEnabled, forKey: Keys.agentUsagePollingEnabled) }
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

    /// What to show on displays without a hardware notch (Mac mini, iMac, external monitors…).
    var nonNotchIslandPlacement: NonNotchIslandPlacement {
        didSet {
            guard oldValue != nonNotchIslandPlacement else { return }
            UserDefaults.standard.set(nonNotchIslandPlacement.rawValue, forKey: Keys.nonNotchIslandPlacement)
            onDisplayPlacementChange?()
        }
    }

    /// Which display hosts the island when several are connected.
    var islandDisplay: IslandDisplayPreference {
        didSet {
            guard oldValue != islandDisplay else { return }
            UserDefaults.standard.set(islandDisplay.rawValue, forKey: Keys.islandDisplay)
            onDisplayPlacementChange?()
        }
    }

    var isPremiumEnabled: Bool = false {
        didSet {
            guard oldValue != isPremiumEnabled else { return }
            onDimensionsChange?()
        }
    }
    var onAvoidMenuOverlapChange: (() -> Void)?
    var onDimensionsChange: (() -> Void)?
    var onDisplayPlacementChange: (() -> Void)?

    private var dimensionPersistTask: Task<Void, Never>?

    private enum Keys {
        static let launchAtLogin = "launchAtLogin"
        static let customIslandWidth = "customIslandWidth"
        static let customIslandHeight = "customIslandHeight"
        static let selectedTheme = "selectedTheme"
        static let hiddenAppBundleIDs = "hiddenAppBundleIDs"
        static let clipboardMonitoringEnabled = "clipboardMonitoringEnabled"
        static let localAPIEnabled = "localAPIEnabled"
        static let agentUsagePollingEnabled = "agentUsagePollingEnabled"
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
        static let nonNotchIslandPlacement = "nonNotchIslandPlacement"
        static let islandDisplay = "islandDisplay"

        static let all = [
            launchAtLogin, customIslandWidth, customIslandHeight, selectedTheme, hiddenAppBundleIDs,
            clipboardMonitoringEnabled, localAPIEnabled, agentUsagePollingEnabled, avoidMenuOverlap,
            urlSchemeAutomationEnabled, lyricsSharingEnabled, appNotificationsEnabled,
            allowedNotificationBundleIDs, allowedNativeNotificationBundleIDs,
            allowedRamboxAggregatorBundleIDs, allowedRamboxServiceBundleIDs, hideNotificationBody,
            dismissSystemBanners, timerAlertSoundName, ramboxAllowlistMigrated,
            nonNotchIslandPlacement, islandDisplay,
        ]
    }

    /// Whether this Mac's built-in display has a camera notch: `nil` when it cannot be seen
    /// (a MacBook with its lid closed), `false` on Macs without a built-in display.
    private static func builtInDisplayHasNotch() -> Bool? {
        for screen in NSScreen.screens {
            guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  CGDisplayIsBuiltin(displayID) != 0 else { continue }
            if case .hardwareNotch = NotchGeometry.classifyTopCutout(ScreenMetrics(screen: screen)) {
                return true
            }
            return false
        }
        return hasInternalBattery() ? nil : false
    }

    private static func hasInternalBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return false
        }
        return sources.contains { source in
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else {
                return false
            }
            return description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        // Before anything below writes a key: did an earlier NotchFlow version run here?
        let isExistingInstall = Keys.all.contains { $0 != Keys.nonNotchIslandPlacement && defaults.object(forKey: $0) != nil }
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
        agentUsagePollingEnabled = defaults.object(forKey: Keys.agentUsagePollingEnabled) as? Bool ?? true
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
        if let saved = defaults.string(forKey: Keys.nonNotchIslandPlacement)
            .flatMap(NonNotchIslandPlacement.init(rawValue:)) {
            nonNotchIslandPlacement = saved
        } else {
            let resolved = NonNotchIslandPlacement.defaultPlacement(
                isExistingInstall: isExistingInstall,
                builtInDisplayHasNotch: Self.builtInDisplayHasNotch()
            )
            nonNotchIslandPlacement = resolved
            // Saved once, so the next launch (which would look like an existing install) keeps it.
            defaults.set(resolved.rawValue, forKey: Keys.nonNotchIslandPlacement)
        }
        islandDisplay = defaults.string(forKey: Keys.islandDisplay)
            .flatMap(IslandDisplayPreference.init(rawValue:)) ?? .followPointer
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

enum NonNotchIslandPlacement: String, CaseIterable, Identifiable, Sendable {
    /// A compact island in the middle of the menu bar, opened by hovering it.
    case topCenter
    /// Nothing is shown while idle; hovering the middle of the menu bar still opens the island.
    /// How displays without a notch behaved before the menu bar capsule existed.
    case hoverOnly
    /// No island on such displays; it opens only from the menu bar icon.
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topCenter: loc("Top center")
        case .hoverOnly: loc("Show on hover only")
        case .off: loc("Off (menu bar icon only)")
        }
    }

    /// No idle capsule is drawn into the menu bar.
    var hidesIdleIsland: Bool {
        self != .topCenter
    }

    /// Default when the user never chose a placement. Existing installs on a notched MacBook
    /// keep what they had (an external display showed nothing until hovered), so an update does
    /// not suddenly put a capsule into their external menu bar. New installs and Macs without
    /// a notch get the visible capsule. A built-in display that cannot be seen (lid closed)
    /// counts as notched for existing installs, which again keeps their old behaviour.
    static func defaultPlacement(isExistingInstall: Bool, builtInDisplayHasNotch: Bool?) -> NonNotchIslandPlacement {
        guard isExistingInstall, builtInDisplayHasNotch != false else { return .topCenter }
        return .hoverOnly
    }
}

enum IslandDisplayPreference: String, CaseIterable, Identifiable, Sendable {
    /// The island moves to whichever display the pointer is on.
    case followPointer
    /// The display that holds the menu bar in System Settings → Displays.
    case mainDisplay
    /// The MacBook's own screen; falls back to the main display when the lid is closed.
    case builtInDisplay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .followPointer: loc("Display with the pointer")
        case .mainDisplay: loc("Main display")
        case .builtInDisplay: loc("Built-in display")
        }
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
