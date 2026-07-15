import AppKit
import Foundation

struct HubNotification: Identifiable, Equatable, Sendable {
    let id: UUID
    let appName: String
    let appBundleID: String
    let serviceBundleID: String
    let sender: String
    let body: String
    let receivedAt: Date
}

@MainActor
final class NotificationHubManager {
    static let callBundleIDs: Set<String> = [
        "com.apple.FaceTime",
        "com.apple.mobilephone",
        "com.apple.TelephonyUtilities"
    ]

    var onStateChange: (() -> Void)?

    private(set) var recentNotifications: [HubNotification] = []
    private(set) var peek: NotificationPeekActivity?

    var isEnabled = false
    var allowedNativeBundleIDs: Set<String> = []
    var allowedRamboxAggregatorBundleIDs: Set<String> = []
    var allowedRamboxServiceBundleIDs: Set<String> = []
    var hideMessageBody = false
    private let peekDuration: TimeInterval = 4

    /// Returns true when the banner was accepted and shown in the notch.
    @discardableResult
    func handleBanner(_ banner: ParsedNotificationBanner) -> Bool {
        guard isEnabled else { return false }
        guard !banner.isCall else { return false }
        guard matchesAllowlist(banner) else { return false }

        let sender = banner.title
        let body = hideMessageBody ? loc("New message") : banner.body
        let openBundleID = preferredOpenBundleID(for: banner)

        let notification = HubNotification(
            id: UUID(),
            appName: banner.appName,
            appBundleID: openBundleID,
            serviceBundleID: banner.serviceBundleID,
            sender: sender,
            body: body,
            receivedAt: .now
        )

        recentNotifications.insert(notification, at: 0)
        if recentNotifications.count > 20 {
            recentNotifications = Array(recentNotifications.prefix(20))
        }

        peek = NotificationPeekActivity(
            id: notification.id,
            appName: notification.appName,
            appBundleID: openBundleID,
            sender: notification.sender,
            body: notification.body,
            receivedAt: notification.receivedAt,
            expiresAt: Date().addingTimeInterval(peekDuration)
        )

        onStateChange?()

        Task {
            try? await Task.sleep(for: .seconds(peekDuration))
            await MainActor.run {
                if self.peek?.id == notification.id {
                    self.peek = nil
                    self.onStateChange?()
                }
            }
        }

        return true
    }

    func dismiss(_ notification: HubNotification) {
        recentNotifications.removeAll { $0.id == notification.id }
        if peek?.id == notification.id {
            peek = nil
        }
        onStateChange?()
    }

    func openApp(for notification: HubNotification) {
        AppIconProvider.openApplication(bundleID: notification.appBundleID)
    }

    private var hasAnyAllowlist: Bool {
        !allowedNativeBundleIDs.isEmpty
            || (!allowedRamboxAggregatorBundleIDs.isEmpty && !allowedRamboxServiceBundleIDs.isEmpty)
    }

    private func matchesAllowlist(_ banner: ParsedNotificationBanner) -> Bool {
        guard hasAnyAllowlist else { return false }

        let delivering = NotificationAppCatalog.canonicalBundleID(for: banner.deliveringBundleID)
        let bannerTexts = [banner.title, banner.body]

        if let foreign = NotificationAppCatalog.matchRunningApp(in: bannerTexts),
           foreign != delivering {
            return allowedNativeBundleIDs.contains(foreign)
        }

        if NotificationAppCatalog.isAggregator(delivering) {
            return matchesRamboxAllowlist(banner, delivering: delivering)
        }

        if allowedNativeBundleIDs.contains(delivering) {
            return true
        }

        if banner.serviceBundleID != "unknown.app" {
            let service = NotificationAppCatalog.canonicalBundleID(for: banner.serviceBundleID)
            if allowedNativeBundleIDs.contains(service) {
                return true
            }
        }

        if banner.hasTrustedSource {
            return false
        }

        let haystack = "\(banner.title) \(banner.body)".lowercased()
        for bundleID in allowedNativeBundleIDs {
            if let keyword = NotificationAppCatalog.keyword(for: bundleID),
               haystack.contains(keyword) {
                return true
            }
        }

        return false
    }

    private func matchesRamboxAllowlist(_ banner: ParsedNotificationBanner, delivering: String) -> Bool {
        guard allowedRamboxAggregatorBundleIDs.contains(delivering) else { return false }
        guard !allowedRamboxServiceBundleIDs.isEmpty else { return false }

        if banner.serviceBundleID != "unknown.app" {
            let service = NotificationAppCatalog.canonicalBundleID(for: banner.serviceBundleID)
            return allowedRamboxServiceBundleIDs.contains(service)
        }

        let haystack = "\(banner.title) \(banner.body)".lowercased()
        for bundleID in allowedRamboxServiceBundleIDs {
            if let keyword = NotificationAppCatalog.keyword(for: bundleID),
               haystack.contains(keyword) {
                return true
            }
        }

        if NotificationAppCatalog.looksLikeGenericMessagingBanner(title: banner.title, body: banner.body) {
            return true
        }

        return false
    }

    private func preferredOpenBundleID(for banner: ParsedNotificationBanner) -> String {
        let delivering = NotificationAppCatalog.canonicalBundleID(for: banner.deliveringBundleID)

        if NotificationAppCatalog.isAggregator(delivering) {
            return delivering
        }

        if let foreign = NotificationAppCatalog.matchRunningApp(in: [banner.title, banner.body]),
           !NotificationAppCatalog.isAggregator(foreign) {
            return foreign
        }

        if banner.serviceBundleID != "unknown.app" {
            return banner.serviceBundleID
        }

        return delivering
    }
}
