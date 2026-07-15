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

    static var suggestedApps: [(name: String, bundleID: String)] {
        NotificationAppCatalog.suggestedApps
    }

    var onStateChange: (() -> Void)?

    private(set) var recentNotifications: [HubNotification] = []
    private(set) var peek: NotificationPeekActivity?

    var isEnabled = false
    var allowedBundleIDs: Set<String> = []
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

    private func matchesAllowlist(_ banner: ParsedNotificationBanner) -> Bool {
        guard !allowedBundleIDs.isEmpty else { return false }

        let delivering = NotificationAppCatalog.canonicalBundleID(for: banner.deliveringBundleID)
        let bannerTexts = [banner.title, banner.body]

        // Baner innej apki (Cursor itd.) — przepuść tylko gdy ta apka jest na liście.
        if let foreign = NotificationAppCatalog.matchRunningApp(in: bannerTexts),
           foreign != delivering {
            return isAllowed(foreign)
        }

        // Natywna apka (nie agregator) włączona na liście.
        if isAllowed(delivering), !NotificationAppCatalog.isAggregator(delivering) {
            return true
        }

        if banner.serviceBundleID != "unknown.app" {
            let service = NotificationAppCatalog.canonicalBundleID(for: banner.serviceBundleID)
            if isAllowed(service) {
                return true
            }
        }

        // Rambox / agregator: sam fakt Rambox na liście NIE przepuszcza każdego banera.
        if NotificationAppCatalog.isAggregator(banner.deliveringBundleID) {
            let ramboxAllowed = isAllowed(delivering)
            let messagingAllowed = !allowedBundleIDs.isDisjoint(with: NotificationAppCatalog.messagingBundleIDs)
            guard ramboxAllowed || messagingAllowed else { return false }

            if banner.serviceBundleID != "unknown.app" {
                return isAllowed(banner.serviceBundleID) || messagingAllowed
            }

            let haystack = "\(banner.title) \(banner.body)".lowercased()
            for bundleID in allowedBundleIDs {
                if let keyword = NotificationAppCatalog.keyword(for: bundleID),
                   haystack.contains(keyword) {
                    return true
                }
            }

            // Wiadomość bez nazwy serwisu (np. sam kontakt + treść) — tylko gdy Rambox jest włączony.
            if ramboxAllowed,
               NotificationAppCatalog.looksLikeGenericMessagingBanner(title: banner.title, body: banner.body) {
                return true
            }

            return false
        }

        if banner.hasTrustedSource {
            return false
        }

        let haystack = "\(banner.title) \(banner.body)".lowercased()
        for bundleID in allowedBundleIDs {
            if let keyword = NotificationAppCatalog.keyword(for: bundleID),
               haystack.contains(keyword) {
                return true
            }
        }

        return false
    }

    private func isAllowed(_ bundleID: String) -> Bool {
        allowedBundleIDs.contains(NotificationAppCatalog.canonicalBundleID(for: bundleID))
    }

    private func preferredOpenBundleID(for banner: ParsedNotificationBanner) -> String {
        if let foreign = NotificationAppCatalog.matchRunningApp(in: [banner.title, banner.body]),
           !NotificationAppCatalog.isAggregator(foreign) {
            return foreign
        }
        if banner.serviceBundleID != "unknown.app" {
            return banner.serviceBundleID
        }
        return banner.deliveringBundleID
    }
}
