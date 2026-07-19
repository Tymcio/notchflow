import AppKit
import Foundation
import os

@MainActor
final class CallManager {
    private static let logger = Logger(subsystem: NotchFlowConstants.bundleID, category: "CallManager")
    /// Grace po zniknięciu banera NC — nieodebrane połączenie znika z notcha szybko.
    private static let ringingBannerGrace: TimeInterval = 2.0
    private static let activeBannerGrace: TimeInterval = 2.5
    /// Po zniknięciu chrome dzwonienia, ale przy żywym Phone.app → rozmowa odebrana.
    private static let promoteToActiveGrace: TimeInterval = 1.2
    /// Awaryjny limit gdy AX „zawiesi” baner w drzewie.
    private static let ringingSafetyTimeout: TimeInterval = 90
    /// False promote (missed ring) while Phone.app idles with no call UI — drop active state.
    private static let activeWithoutBannerTimeout: TimeInterval = 4.0
    private static let dismissMemoryTTL: TimeInterval = 150
    private static let dismissMemoryLimit = 40

    private struct DismissedCallRecord {
        let fingerprint: String?
        let softKey: String
        let dismissedAt: Date
    }

    var onStateChange: (() -> Void)?
    /// Fired when incoming/active call UI is cleared (reset system-banner hide latch).
    var onCleared: (() -> Void)?

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
    /// Ostatni moment, gdy widzieliśmy chrome dzwonienia (Odbierz/Odrzuć / ringing title).
    private var lastSeenRingingChromeAt: Date?

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
        guard isEnabled else {
            Self.callDebugTrace("handleBanner skipped (disabled): \(banner.title)")
            return
        }
        guard isCallBanner(banner) else {
            Self.logger.debug("handleBanner ignored (not call): \(banner.title, privacy: .private)")
            return
        }

        if seedSuppressionOnNextReconcile {
            Self.logger.info("handleBanner seeded/suppressed on enable: \(banner.title, privacy: .private)")
            Self.callDebugTrace("handleBanner seeded/suppressed: \(banner.title)")
            // Don't poison dismiss-memory with synthetic process-only fingerprints.
            if banner.element != nil {
                rememberDismissal(banner: banner, incoming: nil, active: nil)
            }
            return
        }
        if isCallUISuppressed(for: banner) {
            Self.logger.info("handleBanner dismiss-memory hit: \(banner.title, privacy: .private)")
            Self.callDebugTrace("handleBanner dismiss-memory: \(banner.title)")
            return
        }

        lastBanner = banner
        lastSeenCallBannerAt = .now
        if Self.looksLikeRingingChrome(banner) {
            lastSeenRingingChromeAt = .now
        }

        let extracted = Self.callerName(from: banner)
        let appBundleID = Self.preferredCallAppBundleID(from: banner)

        // Already in a call — only refresh caller name, don't fall back to ringing UI.
        if let active = activeCall {
            if Self.isUsableCallerName(extracted), extracted != active.callerName {
                activeCall = ActiveCallActivity(
                    callerName: extracted,
                    appBundleID: active.appBundleID,
                    startedAt: active.startedAt,
                    avatarImageData: Self.avatarData(for: extracted) ?? active.avatarImageData
                )
                onStateChange?()
            }
            return
        }

        let callerName: String
        if Self.isUsableCallerName(extracted) {
            callerName = extracted
        } else if let prior = incomingCall?.callerName, Self.isUsableCallerName(prior) {
            callerName = prior
        } else {
            callerName = loc("Incoming call")
        }

        if let existing = incomingCall {
            // Upgrade placeholder name when a real caller appears.
            if Self.isUsableCallerName(extracted), extracted != existing.callerName {
                incomingCall = IncomingCallActivity(
                    callerName: extracted,
                    appBundleID: appBundleID,
                    receivedAt: existing.receivedAt,
                    avatarImageData: Self.avatarData(for: extracted) ?? existing.avatarImageData
                )
                Self.callDebugTrace("UI update caller=\(extracted) app=\(appBundleID)")
                onStateChange?()
            } else if existing.avatarImageData == nil,
                      Self.isUsableCallerName(existing.callerName),
                      let avatar = Self.avatarData(for: existing.callerName) {
                incomingCall = IncomingCallActivity(
                    callerName: existing.callerName,
                    appBundleID: existing.appBundleID,
                    receivedAt: existing.receivedAt,
                    avatarImageData: avatar
                )
                onStateChange?()
            }
            return
        }

        let nextIncoming = IncomingCallActivity(
            callerName: callerName,
            appBundleID: appBundleID,
            receivedAt: .now,
            avatarImageData: Self.isUsableCallerName(callerName) ? Self.avatarData(for: callerName) : nil
        )

        Self.logger.info(
            "incoming call UI: caller=\(callerName, privacy: .private) app=\(appBundleID, privacy: .public)"
        )
        Self.callDebugTrace("UI show caller=\(callerName) app=\(appBundleID)")
        incomingCall = nextIncoming
        ContinuityCallActions.captureAllowed = true
        onStateChange?()
    }

    private static func callDebugTrace(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) CallManager \(message)\n"
        let url = URL(fileURLWithPath: "/tmp/notchflow-call-debug.log")
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    func reconcile(with banners: [ParsedNotificationBanner]) {
        guard isEnabled else { return }
        pruneDismissMemory()

        let callBanners = banners.filter(isCallBanner)
        let realCallBanners = callBanners.filter { !Self.isSpuriousCallBanner($0) }
        let hostRunning = AXHelpers.isCallUIHostRunning
        let hasRingingChrome = realCallBanners.contains(where: Self.looksLikeRingingChrome)

        if seedSuppressionOnNextReconcile {
            seedSuppressionOnNextReconcile = false
            // Never seed dismiss-memory for call banners — FACETIME stubs share fingerprints
            // across rings and would block the next Continuity call.
            if incomingCall != nil || activeCall != nil || lastBanner != nil {
                clearCall()
            }
            return
        }

        if let callBanner = realCallBanners.first {
            lastSeenCallBannerAt = .now
            if Self.looksLikeRingingChrome(callBanner) {
                lastSeenRingingChromeAt = .now
            }
            if !isCallUISuppressed(for: callBanner) {
                handleBanner(callBanner)
            }
        } else if hostRunning, incomingCall != nil || activeCall != nil {
            // Keep session alive while Phone hosts a process-only Continuity ring.
            lastSeenCallBannerAt = .now
        }

        if incomingCall != nil {
            // Promote ONLY after real Answer/Decline chrome vanished while Phone stayed up.
            if hostRunning, !hasRingingChrome, let ringRef = lastSeenRingingChromeAt,
               Date().timeIntervalSince(ringRef) >= Self.promoteToActiveGrace {
                promoteIncomingToActive()
                return
            }

            // Missed / cancelled — clear when Phone/FaceTime host is gone.
            // Do NOT clear while hostRunning with only a process-only synthetic (no AX buttons).
            if !hostRunning, !hasRingingChrome {
                let lastSeen = lastSeenCallBannerAt ?? incomingCall?.receivedAt ?? .now
                if Date().timeIntervalSince(lastSeen) >= Self.ringingBannerGrace {
                    Self.callDebugTrace("clear incoming — call host gone")
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
            // Real in-call UI is hosted by Phone.app; when it quits, the call is over.
            // Do not auto-clear while the host is still running (user can tap End).
            if !hostRunning {
                let lastSeen = lastSeenCallBannerAt ?? activeCall?.startedAt ?? .now
                if Date().timeIntervalSince(lastSeen) >= Self.activeBannerGrace {
                    Self.callDebugTrace("clear active — call host gone")
                    clearCall()
                }
            }
        }
    }

    func answerCall(using observer: NotificationCenterObserver) {
        ContinuityCallBannerCover.stopCovering()
        var answered = false
        if let banner = lastBanner {
            answered = observer.pressAnswer(on: banner)
        } else {
            answered = ContinuityCallActions.pressAnswer()
            Self.callDebugTrace("answer without banner via Continuity=\(answered)")
        }
        // Always show in-call UI after a user tap; Continuity may still connect a moment later.
        promoteIncomingToActive()
        if !answered {
            // Retry once — card animation / cover teardown can race the first click.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                _ = ContinuityCallActions.pressAnswer()
            }
        }
    }

    func declineCall(using observer: NotificationCenterObserver) {
        ContinuityCallBannerCover.stopCovering()
        rememberDismissal(banner: lastBanner, incoming: incomingCall, active: activeCall)
        if let banner = lastBanner {
            _ = observer.pressDecline(on: banner)
        } else {
            _ = ContinuityCallActions.pressDecline()
        }
        clearCall()
    }

    func endCall(using observer: NotificationCenterObserver) {
        ContinuityCallBannerCover.stopCovering()
        rememberDismissal(banner: lastBanner, incoming: incomingCall, active: activeCall)
        if let banner = lastBanner {
            _ = observer.pressDecline(on: banner)
        } else {
            _ = ContinuityCallActions.pressDecline()
        }
        clearCall()
    }

    func dismissCallUI() {
        rememberDismissal(banner: lastBanner, incoming: incomingCall, active: activeCall)
        clearCall()
    }

    private func promoteIncomingToActive() {
        let callerName: String
        if let incoming = incomingCall, Self.isUsableCallerName(incoming.callerName) {
            callerName = incoming.callerName
        } else if let banner = lastBanner {
            let extracted = Self.callerName(from: banner)
            callerName = Self.isUsableCallerName(extracted) ? extracted : loc("Incoming call")
        } else {
            callerName = loc("Incoming call")
        }
        let appBundleID = incomingCall?.appBundleID
            ?? lastBanner.map(Self.preferredCallAppBundleID)
            ?? "com.apple.mobilephone"

        Self.callDebugTrace("promote to active caller=\(callerName) app=\(appBundleID)")
        let avatar = incomingCall?.avatarImageData
            ?? (Self.isUsableCallerName(callerName) ? Self.avatarData(for: callerName) : nil)
        incomingCall = nil
        activeCall = ActiveCallActivity(
            callerName: callerName,
            appBundleID: appBundleID,
            startedAt: .now,
            avatarImageData: avatar
        )
        lastSeenCallBannerAt = .now
        // Ring over — stop screen captures (they light the recording indicator).
        ContinuityCallActions.captureAllowed = false
        onStateChange?()
    }

    private func clearCall() {
        guard incomingCall != nil || activeCall != nil || lastBanner != nil else { return }

        incomingCall = nil
        activeCall = nil
        lastBanner = nil
        lastSeenCallBannerAt = nil
        lastSeenRingingChromeAt = nil
        ContinuityCallActions.captureAllowed = false
        onStateChange?()
        onCleared?()
    }

    private func isCallBanner(_ banner: ParsedNotificationBanner) -> Bool {
        banner.isLikelyCall
    }

    private static func looksLikeRingingChrome(_ banner: ParsedNotificationBanner) -> Bool {
        // Only real Answer/Decline AX controls on a non-spurious banner.
        // TCC "Allow Contacts" / calendar widgets with 2+ buttons must not count.
        guard !isSpuriousCallBanner(banner) else { return false }
        return banner.hasAnswerControl || banner.hasDeclineControl
    }

    private static func isProcessOnlyRingBanner(_ banner: ParsedNotificationBanner) -> Bool {
        banner.body == "process-only-ring" || (banner.element == nil && !banner.hasAnswerControl && !banner.hasDeclineControl)
    }

    /// Privacy prompts / calendar / widgets — not a Continuity ring.
    /// Note: do NOT treat "Incoming call" / looksLikeCallNotification as spurious.
    private static func isSpuriousCallBanner(_ banner: ParsedNotificationBanner) -> Bool {
        if NotificationAppCatalog.isCalendarChromeLabel(banner.title) { return true }
        let lower = banner.title.lowercased()
        if lower.contains("chce uzyskać dostęp") || lower.contains("wants to access")
            || lower.contains("would like to access") {
            return true
        }
        if lower.contains("widżet") || lower.contains("widget") { return true }
        if lower.hasPrefix("kamera"), lower.contains("iphone") { return true }
        if lower.hasPrefix("camera"), lower.contains("iphone") { return true }
        return false
    }

    private static func preferredCallAppBundleID(from banner: ParsedNotificationBanner) -> String {
        for candidate in [banner.axDeliveringBundleID, banner.deliveringBundleID, banner.serviceBundleID] {
            guard let candidate else { continue }
            let canonical = NotificationAppCatalog.canonicalBundleID(for: candidate)
            if NotificationAppCatalog.callUIHostBundleIDs.contains(canonical)
                || NotificationAppCatalog.callBundleIDs.contains(canonical) {
                return canonical == "com.apple.TelephonyUtilities"
                    ? "com.apple.mobilephone"
                    : canonical
            }
        }
        return "com.apple.mobilephone"
    }

    private static func callerName(from banner: ParsedNotificationBanner) -> String {
        let lines = [banner.title]
            + banner.body.components(separatedBy: " · ")
            + banner.iconLabels
        return NotificationAppCatalog.bestCallerName(from: lines, appName: banner.appName)
    }

    private static func isUsableCallerName(_ name: String) -> Bool {
        NotificationAppCatalog.isPlausibleCallerName(name)
    }

    private static func avatarData(for callerName: String) -> Data? {
        guard let image = ContactPhotoProvider.thumbnail(forCallerName: callerName) else { return nil }
        return image.tiffRepresentation.flatMap {
            NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:])
        }
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
