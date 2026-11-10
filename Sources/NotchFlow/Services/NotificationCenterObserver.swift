import AppKit
import ApplicationServices
import Foundation

/// Detects Notification Center banners and hands them to the notification hub.
///
/// Detection is event-driven: an `AXObserver` on each Notification Center process triggers a
/// short burst of scans when its UI changes, and a slow safety poll catches anything the
/// observer missed. The Accessibility tree walk itself runs on `NotificationBannerScanner`'s
/// background queue; only bookkeeping happens on the main actor.
@MainActor
final class NotificationCenterObserver {
    var onBannerDetected: ((ParsedNotificationBanner) -> Void)?

    /// Fallback scan interval while enabled. Banners are found through AX events first.
    static let safetyPollInterval: Duration = .seconds(5)
    /// Scans after an AX event — the first tick after a toast appears is often still empty.
    static let burstScanDelays: [Int] = [0, 150, 400, 800]

    private let scanner = NotificationBannerScanner()
    private var isEnabled = false
    private var safetyPollTask: Task<Void, Never>?
    private var burstTask: Task<Void, Never>?
    private var scanInFlight = false
    private var scanPending = false
    private var seenFingerprints: [String: Date] = [:]
    private var axObservers: [pid_t: AXObserver] = [:]

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            startSafetyPoll()
        } else {
            safetyPollTask?.cancel()
            safetyPollTask = nil
            burstTask?.cancel()
            burstTask = nil
            removeAXObservers()
            scanPending = false
            seenFingerprints.removeAll()
        }
    }

    /// Closes the system banner (AX "Close" action) once it is shown in the notch.
    /// Retries, because the action is not available yet during the slide-in animation.
    func dismissBanner(_ banner: ParsedNotificationBanner) {
        guard banner.element != nil else { return }
        let scanner = scanner
        Task {
            for attempt in 0..<8 {
                let closed = await scanner.run {
                    banner.element.map(NotificationBannerActions.dismiss) ?? true
                }
                if closed { return }
                try? await Task.sleep(for: .milliseconds(attempt == 0 ? 120 : 180))
            }
            NotchFlowLog.notifications.debug("dismissBanner: close action not found")
        }
    }

    /// Best-effort quick reply via AX text field / Reply button on the live NC banner.
    @discardableResult
    func sendReply(on banner: ParsedNotificationBanner, text: String) -> Bool {
        NotificationBannerActions.sendReply(on: banner, text: text)
    }

    // MARK: - Scheduling

    private func startSafetyPoll() {
        safetyPollTask?.cancel()
        safetyPollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.scanForBanners()
                try? await Task.sleep(for: Self.safetyPollInterval, tolerance: .seconds(1))
            }
        }
    }

    private func handleAXEvent(newWindow: AXUIElement?) {
        guard isEnabled else { return }
        if let newWindow, let registration = observerRegistration(forWindow: newWindow) {
            Task { [scanner] in
                await scanner.run {
                    NotificationBannerScanner.register(registration.handle, on: registration.element)
                }
            }
        }
        scheduleBurstScans()
    }

    /// Restarts a short burst of scans; repeated events coalesce into one burst.
    private func scheduleBurstScans() {
        burstTask?.cancel()
        burstTask = Task { [weak self] in
            var lastDelay = 0
            for delay in Self.burstScanDelays {
                let delta = delay - lastDelay
                if delta > 0 {
                    try? await Task.sleep(for: .milliseconds(delta))
                }
                lastDelay = delay
                guard !Task.isCancelled else { return }
                await self?.scanForBanners()
            }
        }
    }

    // MARK: - Scanning

    private func scanForBanners() async {
        guard isEnabled, AXIsProcessTrusted() else { return }
        if scanInFlight {
            scanPending = true
            return
        }
        scanInFlight = true
        defer { scanInFlight = false }

        repeat {
            scanPending = false
            let pids = AXHelpers.notificationCenterPIDs()
            guard !pids.isEmpty else { return }
            await installAXObserversIfNeeded(pids: pids)
            let banners = await scanner.scan(pids: pids)
            guard isEnabled else { return }
            deliver(banners)
        } while scanPending && isEnabled
    }

    private func deliver(_ banners: [ParsedNotificationBanner]) {
        let now = Date()
        seenFingerprints = seenFingerprints.filter { now.timeIntervalSince($0.value) < 30 }

        for banner in banners {
            // Calls-in-notch is shelved: Continuity has no public API for caller identity or
            // Answer/Decline, so call banners are left to macOS and never shown as messages.
            guard !banner.isLikelyCall else { continue }
            guard seenFingerprints[banner.fingerprint] == nil else { continue }
            seenFingerprints[banner.fingerprint] = now
            onBannerDetected?(banner)
        }
    }

    // MARK: - AXObserver

    private func observerRegistration(forWindow window: AXUIElement) -> NotificationBannerScanner.WindowRegistration? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success, let observer = axObservers[pid] else { return nil }
        AXUIElementSetMessagingTimeout(window, AXHelpers.messagingTimeout)
        return NotificationBannerScanner.WindowRegistration(
            handle: AXObserverHandle(observer: observer, pid: pid, refcon: refcon),
            element: window
        )
    }

    private var refcon: UnsafeMutableRawPointer {
        Unmanaged.passUnretained(self).toOpaque()
    }

    private func installAXObserversIfNeeded(pids: [pid_t]) async {
        // Forget observers of Notification Center processes that have exited.
        for pid in axObservers.keys where !pids.contains(pid) {
            if let observer = axObservers.removeValue(forKey: pid) {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
            }
        }

        for pid in pids where axObservers[pid] == nil {
            let callback: AXObserverCallback = { _, element, notification, refcon in
                guard let refcon else { return }
                let instance = Unmanaged<NotificationCenterObserver>.fromOpaque(refcon).takeUnretainedValue()
                let isNewWindow = (notification as String) == kAXWindowCreatedNotification
                // The run loop source is attached to the main run loop.
                MainActor.assumeIsolated {
                    instance.handleAXEvent(newWindow: isNewWindow ? element : nil)
                }
            }
            var created: AXObserver?
            guard AXObserverCreate(pid, callback, &created) == .success, let created else {
                NotchFlowLog.notifications.debug("AXObserverCreate failed for pid \(pid)")
                continue
            }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
            axObservers[pid] = created
            let handle = AXObserverHandle(observer: created, pid: pid, refcon: refcon)
            await scanner.run { NotificationBannerScanner.register(handle) }
        }
    }

    private func removeAXObservers() {
        for observer in axObservers.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        axObservers.removeAll()
    }
}
