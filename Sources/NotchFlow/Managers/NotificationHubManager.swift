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
    let supportsQuickReply: Bool
}

@MainActor
final class NotificationHubManager {
    static let callBundleIDs: Set<String> = NotificationAppCatalog.callBundleIDs

    var onStateChange: (() -> Void)?

    private(set) var recentNotifications: [HubNotification] = []
    private(set) var peek: NotificationPeekActivity?
    /// Banner retained for best-effort AX quick reply while the peek is visible.
    private(set) var activeReplyBanner: ParsedNotificationBanner?
    private(set) var supportsQuickReply = false

    var isEnabled = false
    var allowedNativeBundleIDs: Set<String> = []
    var hideMessageBody = false
    private let peekDuration: TimeInterval = 8

    /// Returns true when the banner was accepted and shown in the notch.
    @discardableResult
    func handleBanner(_ banner: ParsedNotificationBanner) -> Bool {
        guard isEnabled else { return false }
        guard !banner.isCall, !banner.isLikelyCall else { return false }
        guard !NotificationAppCatalog.looksLikeCallNotification(
            title: banner.title,
            body: banner.body,
            iconLabels: banner.iconLabels
        ) else { return false }
        // Match allowlisted app first — privacy banners may have no readable preview.
        guard let matchedBundleID = matchedAllowedApp(for: banner) else { return false }

        let appName = NotificationAppCatalog.name(for: matchedBundleID)
        // Presence-only drip for every allowlisted app — no message body in the island.
        let presenceBody = loc("Notification")
        let isMail = NotificationAppCatalog.isEmailApp(matchedBundleID)
        let canReply = banner.supportsQuickReply && !isMail

        let notification = HubNotification(
            id: UUID(),
            appName: appName,
            appBundleID: matchedBundleID,
            serviceBundleID: matchedBundleID,
            sender: appName,
            body: presenceBody,
            receivedAt: .now,
            supportsQuickReply: canReply
        )

        recentNotifications.insert(notification, at: 0)
        if recentNotifications.count > 20 {
            recentNotifications = Array(recentNotifications.prefix(20))
        }

        activeReplyBanner = canReply ? banner : nil
        supportsQuickReply = canReply

        peek = NotificationPeekActivity(
            id: notification.id,
            appName: notification.appName,
            appBundleID: matchedBundleID,
            openBundleID: matchedBundleID,
            sender: appName,
            body: presenceBody,
            receivedAt: notification.receivedAt,
            expiresAt: Date().addingTimeInterval(peekDuration),
            supportsQuickReply: false
        )

        onStateChange?()

        Task {
            try? await Task.sleep(for: .seconds(peekDuration))
            await MainActor.run {
                if self.peek?.id == notification.id {
                    self.clearPeek()
                }
            }
        }

        return true
    }

    func dismiss(_ notification: HubNotification) {
        recentNotifications.removeAll { $0.id == notification.id }
        if peek?.id == notification.id {
            clearPeek()
        } else {
            onStateChange?()
        }
    }

    func openApp(for notification: HubNotification) {
        AppIconProvider.openApplication(bundleID: notification.appBundleID)
    }

    func openActivePeekApp() {
        guard let peek else { return }
        AppIconProvider.openApplication(bundleID: peek.openBundleID)
        clearPeek()
    }

    /// Attempts AX quick reply on the retained banner. Returns false when unavailable.
    @discardableResult
    func replyToActivePeek(text: String, using observer: NotificationCenterObserver) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, supportsQuickReply, let banner = activeReplyBanner else {
            return false
        }
        let ok = observer.sendReply(on: banner, text: trimmed)
        if ok {
            clearPeek()
        }
        return ok
    }

    private func clearPeek() {
        peek = nil
        activeReplyBanner = nil
        supportsQuickReply = false
        onStateChange?()
    }

    /// Exact trusted bundle or exact icon-label match for an allowlisted supported app.
    private func matchedAllowedApp(for banner: ParsedNotificationBanner) -> String? {
        guard !allowedNativeBundleIDs.isEmpty else { return nil }

        // Icon / catalog identity wins over a foreign Electron helper deliverer.
        if let matched = NotificationAppCatalog.matchMessagingAppFromIconLabels(in: banner.iconLabels),
           NotificationAppCatalog.isSupportedNotificationApp(matched.bundleID),
           allowedNativeBundleIDs.contains(matched.bundleID) {
            return matched.bundleID
        }

        let delivering = NotificationAppCatalog.canonicalBundleID(for: banner.deliveringBundleID)
        if isNonSupportedPoster(banner, delivering: delivering) {
            return matchAllowlistedByExactAppName(banner)
        }

        if NotificationAppCatalog.isSupportedNotificationApp(delivering),
           allowedNativeBundleIDs.contains(delivering) {
            return delivering
        }

        if isNativeSMSAllowlisted(banner) {
            return Self.mobileSMSBundleID
        }

        if let axHint = banner.axDeliveringBundleID {
            let hinted = NotificationAppCatalog.canonicalBundleID(for: axHint)
            if NotificationAppCatalog.isSupportedNotificationApp(hinted),
               allowedNativeBundleIDs.contains(hinted) {
                return hinted
            }
        }

        if banner.serviceBundleID != "unknown.app" {
            let service = NotificationAppCatalog.canonicalBundleID(for: banner.serviceBundleID)
            if NotificationAppCatalog.isSupportedNotificationApp(service),
               allowedNativeBundleIDs.contains(service) {
                return service
            }
        }

        return matchAllowlistedByExactAppName(banner)
    }

    /// Fallback when AX only exposes the app title (e.g. „Signal”) without a bundle hint.
    private func matchAllowlistedByExactAppName(_ banner: ParsedNotificationBanner) -> String? {
        let labels = ([banner.appName, banner.title] + banner.iconLabels)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let matched = NotificationAppCatalog.matchMessagingAppByExactName(in: labels),
              NotificationAppCatalog.isSupportedNotificationApp(matched.bundleID),
              allowedNativeBundleIDs.contains(matched.bundleID) else {
            return nil
        }
        return matched.bundleID
    }

    private func isNonSupportedPoster(
        _ banner: ParsedNotificationBanner,
        delivering: String
    ) -> Bool {
        if NotificationAppCatalog.isNativeMessagesSource(banner.axDeliveringBundleID) {
            return false
        }

        // Catalog icon/service already identifies a supported app — keep it.
        if NotificationAppCatalog.matchMessagingAppFromIconLabels(in: banner.iconLabels) != nil {
            return false
        }
        if NotificationAppCatalog.isSupportedNotificationApp(
            NotificationAppCatalog.canonicalBundleID(for: banner.serviceBundleID)
        ) {
            return false
        }

        if let foreign = NotificationAppCatalog.matchRunningApp(in: banner.iconLabels),
           !NotificationAppCatalog.isSupportedNotificationApp(foreign) {
            return true
        }

        guard delivering != "unknown.app" else { return false }
        return !NotificationAppCatalog.isSupportedNotificationApp(delivering)
    }

    private static let mobileSMSBundleID = "com.apple.MobileSMS"

    private var nativeSMSEnabled: Bool {
        allowedNativeBundleIDs.contains(Self.mobileSMSBundleID)
    }

    private func hasNativeSMSIconProof(_ banner: ParsedNotificationBanner) -> Bool {
        guard nativeSMSEnabled else { return false }

        if NotificationAppCatalog.isNativeMessagesSource(banner.axDeliveringBundleID) {
            return true
        }

        for label in banner.iconLabels where NotificationAppCatalog.isNativeMessagesSource(label) {
            return true
        }

        if NotificationAppCatalog.matchMessagingAppFromIconLabels(in: banner.iconLabels)?.bundleID
            == Self.mobileSMSBundleID {
            return true
        }

        for candidate in [banner.serviceBundleID, banner.deliveringBundleID] {
            let canonical = NotificationAppCatalog.canonicalBundleID(for: candidate)
            if canonical == Self.mobileSMSBundleID { return true }
        }

        return false
    }

    private func isNativeSMSAllowlisted(_ banner: ParsedNotificationBanner) -> Bool {
        guard nativeSMSEnabled else { return false }
        if NotificationAppCatalog.isBlockedNotificationContent(title: banner.title, body: banner.body) {
            return false
        }
        return hasNativeSMSIconProof(banner)
    }
}
