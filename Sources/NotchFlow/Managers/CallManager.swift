import Foundation

@MainActor
final class CallManager {
    private static let incomingTimeout: TimeInterval = 40

    var onStateChange: (() -> Void)?

    private(set) var incomingCall: IncomingCallActivity?
    private(set) var activeCall: ActiveCallActivity?
    private(set) var lastBanner: ParsedNotificationBanner?

    var isEnabled = false {
        didSet {
            if !isEnabled {
                clearCall()
            }
        }
    }

    func handleBanner(_ banner: ParsedNotificationBanner) {
        guard isEnabled, banner.isCall else { return }
        guard banner.answerButton != nil, banner.declineButton != nil else { return }

        lastBanner = banner
        let callerName = Self.callerName(from: banner)

        if incomingCall == nil, activeCall == nil {
            incomingCall = IncomingCallActivity(
                callerName: callerName,
                appBundleID: banner.appBundleID,
                receivedAt: .now
            )
            onStateChange?()
        }
    }

    func reconcile(with banners: [ParsedNotificationBanner]) {
        guard isEnabled else { return }

        if let incomingCall {
            let callBanners = banners.filter(\.isCall)
            let stillPresent = callBanners.contains { bannerMatches($0, incomingCall) }
            let timedOut = Date().timeIntervalSince(incomingCall.receivedAt) > Self.incomingTimeout

            if !stillPresent || timedOut {
                clearCall()
            }
            return
        }

        if activeCall != nil {
            // Active calls are ended explicitly; the system banner usually disappears after answer.
            return
        }
    }

    func answerCall(using observer: NotificationCenterObserver) {
        guard let banner = lastBanner else { return }
        observer.pressAnswer(on: banner)

        let callerName = incomingCall?.callerName ?? Self.callerName(from: banner)
        incomingCall = nil
        activeCall = ActiveCallActivity(
            callerName: callerName,
            appBundleID: banner.appBundleID,
            startedAt: .now
        )
        onStateChange?()
    }

    func declineCall(using observer: NotificationCenterObserver) {
        if let banner = lastBanner {
            observer.pressDecline(on: banner)
        }
        clearCall()
    }

    func endCall() {
        clearCall()
    }

    private func clearCall() {
        guard incomingCall != nil || activeCall != nil || lastBanner != nil else { return }

        incomingCall = nil
        activeCall = nil
        lastBanner = nil
        onStateChange?()
    }

    private func bannerMatches(_ banner: ParsedNotificationBanner, _ incoming: IncomingCallActivity) -> Bool {
        guard banner.answerButton != nil, banner.declineButton != nil else { return false }

        if let lastBanner, banner.fingerprint == lastBanner.fingerprint {
            return true
        }

        return banner.appBundleID == incoming.appBundleID
            && Self.callerName(from: banner) == incoming.callerName
    }

    private static func callerName(from banner: ParsedNotificationBanner) -> String {
        let title = banner.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = banner.body.trimmingCharacters(in: .whitespacesAndNewlines)

        if title.isEmpty { return body.isEmpty ? banner.appName : body }
        if title == banner.appName, !body.isEmpty { return body }
        if body.isEmpty || body == title { return title }
        return title
    }
}
