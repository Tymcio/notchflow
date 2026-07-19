import Foundation
import os

@MainActor
final class CallManager {
    private static let logger = Logger(subsystem: NotchFlowConstants.bundleID, category: "CallManager")
    /// Grace po zniknięciu banera NC — nieodebrane połączenie znika z notcha szybko.
    private static let ringingBannerGrace: TimeInterval = 2.0
    private static let activeBannerGrace: TimeInterval = 3.0
    /// Awaryjny limit gdy AX „zawiesi” baner w drzewie.
    private static let ringingSafetyTimeout: TimeInterval = 90
    private static let dismissMemoryTTL: TimeInterval = 150
    private static let dismissMemoryLimit = 40

    private struct DismissedCallRecord {
        let fingerprint: String?
        let softKey: String
        let dismissedAt: Date
    }

    var onStateChange: (() -> Void)?

    private(set) var incomingCall: IncomingCallActivity?
    private(set) var activeCall: ActiveCallActivity?
    private(set) var lastBanner: ParsedNotificationBanner?

    /// True gdy w notchu jest ringing/active — observer może przyspieszyć safety poll.
    var needsFrequentScan: Bool {
        incomingCall != nil || activeCall != nil
    }

    private var dismissedRecords: [DismissedCallRecord] = []
    /// Pierwszy skan po włączeniu — zablokuj banery już widoczne w NC.
    private var seedSuppressionOnNextReconcile = false
    private var lastSeenCallBannerAt: Date?

    var isEnabled = false {
        didSet {
            guard oldValue != isEnabled else { return }
            if isEnabled {
                seedSuppressionOnNextReconcile = true
            } else {
                rememberDismissal(banner: lastBanner, incoming: incomingCall, active: activeCall)
                clearCall()
            }
        }
    }

    func handleBanner(_ banner: ParsedNotificationBanner) {
        guard isEnabled else { return }
        guard isCallBanner(banner) else {
            Self.logger.debug("handleBanner ignored (not call): \(banner.title, privacy: .private)")
            return
        }

        if seedSuppressionOnNextReconcile {
            Self.logger.info("handleBanner seeded/suppressed on enable: \(banner.title, privacy: .private)")
            rememberDismissal(banner: banner, incoming: nil, active: nil)
            return
        }
        if isCallUISuppressed(for: banner) {
            Self.logger.info("handleBanner dismiss-memory hit: \(banner.title, privacy: .private)")
            return
        }

        lastBanner = banner
        lastSeenCallBannerAt = .now

        let extracted = Self.callerName(from: banner)
        let callerName: String
        if Self.isUsableCallerName(extracted) {
            callerName = extracted
        } else if let prior = incomingCall?.callerName, Self.isUsableCallerName(prior) {
            callerName = prior
        } else {
            callerName = extracted
        }
        let appBundleID = Self.preferredCallAppBundleID(from: banner)

        guard activeCall == nil else { return }

        let nextIncoming = IncomingCallActivity(
            callerName: callerName,
            appBundleID: appBundleID,
            receivedAt: incomingCall?.receivedAt ?? .now
        )

        if incomingCall == nextIncoming { return }

        Self.logger.info(
            "incoming call UI: caller=\(callerName, privacy: .private) app=\(appBundleID, privacy: .public)"
        )
        incomingCall = nextIncoming
        onStateChange?()
    }

    func reconcile(with banners: [ParsedNotificationBanner]) {
        guard isEnabled else { return }
        pruneDismissMemory()

        let callBanners = banners.filter(isCallBanner)

        if seedSuppressionOnNextReconcile {
            seedSuppressionOnNextReconcile = false
            for banner in callBanners {
                rememberDismissal(banner: banner, incoming: nil, active: nil)
            }
            if incomingCall != nil || activeCall != nil || lastBanner != nil {
                clearCall()
            }
            return
        }

        if let callBanner = callBanners.first {
            lastSeenCallBannerAt = .now
            if !isCallUISuppressed(for: callBanner) {
                handleBanner(callBanner)
            }
        }

        if incomingCall != nil {
            if callBanners.isEmpty {
                let lastSeen = lastSeenCallBannerAt ?? incomingCall?.receivedAt ?? .now
                if Date().timeIntervalSince(lastSeen) >= Self.ringingBannerGrace {
                    clearCall()
                    return
                }
            }
            if let incoming = incomingCall,
               Date().timeIntervalSince(incoming.receivedAt) > Self.ringingSafetyTimeout {
                clearCall()
            }
            return
        }

        if activeCall != nil {
            if callBanners.isEmpty {
                let lastSeen = lastSeenCallBannerAt ?? activeCall?.startedAt ?? .now
                if Date().timeIntervalSince(lastSeen) >= Self.activeBannerGrace {
                    clearCall()
                }
            }
        }
    }

    func answerCall(using observer: NotificationCenterObserver) {
        guard let banner = lastBanner else { return }
        observer.pressAnswer(on: banner)

        let callerName = incomingCall?.callerName ?? Self.callerName(from: banner)
        let appBundleID = Self.preferredCallAppBundleID(from: banner)
        incomingCall = nil
        activeCall = ActiveCallActivity(
            callerName: callerName,
            appBundleID: appBundleID,
            startedAt: .now
        )
        lastSeenCallBannerAt = .now
        onStateChange?()
    }

    func declineCall(using observer: NotificationCenterObserver) {
        rememberDismissal(banner: lastBanner, incoming: incomingCall, active: activeCall)
        if let banner = lastBanner {
            observer.pressDecline(on: banner)
        }
        clearCall()
    }

    func endCall(using observer: NotificationCenterObserver) {
        rememberDismissal(banner: lastBanner, incoming: incomingCall, active: activeCall)
        if let banner = lastBanner {
            observer.pressDecline(on: banner)
        }
        clearCall()
    }

    func dismissCallUI() {
        rememberDismissal(banner: lastBanner, incoming: incomingCall, active: activeCall)
        clearCall()
    }

    private func clearCall() {
        guard incomingCall != nil || activeCall != nil || lastBanner != nil else { return }

        incomingCall = nil
        activeCall = nil
        lastBanner = nil
        lastSeenCallBannerAt = nil
        onStateChange?()
    }

    private func isCallBanner(_ banner: ParsedNotificationBanner) -> Bool {
        banner.isLikelyCall
    }

    private static func preferredCallAppBundleID(from banner: ParsedNotificationBanner) -> String {
        for candidate in [banner.axDeliveringBundleID, banner.deliveringBundleID, banner.serviceBundleID] {
            guard let candidate else { continue }
            let canonical = NotificationAppCatalog.canonicalBundleID(for: candidate)
            if NotificationAppCatalog.callBundleIDs.contains(canonical) {
                return canonical
            }
        }
        return NotificationAppCatalog.canonicalBundleID(for: banner.deliveringBundleID)
    }

    private static func callerName(from banner: ParsedNotificationBanner) -> String {
        let lines = [banner.title]
            + banner.body.components(separatedBy: " · ")
            + banner.iconLabels
        return NotificationAppCatalog.bestCallerName(from: lines, appName: banner.appName)
    }

    private static func isUsableCallerName(_ name: String) -> Bool {
        !NotificationAppCatalog.isSystemCallUILabel(name)
    }

    private static func softKey(
        banner: ParsedNotificationBanner?,
        incoming: IncomingCallActivity?,
        active: ActiveCallActivity?
    ) -> String? {
        if let banner {
            let caller = callerName(from: banner)
            guard isUsableCallerName(caller) else { return nil }
            let app = preferredCallAppBundleID(from: banner)
            return "\(app)|\(caller.lowercased())"
        }
        if let incoming, isUsableCallerName(incoming.callerName) {
            return "\(incoming.appBundleID)|\(incoming.callerName.lowercased())"
        }
        if let active, isUsableCallerName(active.callerName) {
            return "\(active.appBundleID)|\(active.callerName.lowercased())"
        }
        return nil
    }

    private func rememberDismissal(
        banner: ParsedNotificationBanner?,
        incoming: IncomingCallActivity?,
        active: ActiveCallActivity?
    ) {
        let soft = Self.softKey(banner: banner, incoming: incoming, active: active)
        let fingerprint = banner?.fingerprint
        guard soft != nil || fingerprint != nil else { return }

        dismissedRecords.removeAll {
            (fingerprint != nil && $0.fingerprint == fingerprint)
                || (soft != nil && $0.softKey == soft)
        }
        dismissedRecords.insert(
            DismissedCallRecord(
                fingerprint: fingerprint,
                softKey: soft ?? fingerprint ?? "unknown",
                dismissedAt: .now
            ),
            at: 0
        )
        if dismissedRecords.count > Self.dismissMemoryLimit {
            dismissedRecords = Array(dismissedRecords.prefix(Self.dismissMemoryLimit))
        }
    }

    private func pruneDismissMemory() {
        let now = Date()
        dismissedRecords.removeAll {
            now.timeIntervalSince($0.dismissedAt) > Self.dismissMemoryTTL
        }
    }

    private func isCallUISuppressed(for banner: ParsedNotificationBanner) -> Bool {
        pruneDismissMemory()
        let soft = Self.softKey(banner: banner, incoming: nil, active: nil)
        return dismissedRecords.contains {
            $0.fingerprint == banner.fingerprint
                || (soft != nil && $0.softKey == soft)
        }
    }
}
