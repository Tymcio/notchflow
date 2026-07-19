import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import os

struct ParsedNotificationBanner {
    /// Aplikacja, która wysłała banner macOS.
    let deliveringBundleID: String
    /// Wywnioskowany serwis wiadomości (np. WhatsApp), jeśli znany.
    let serviceBundleID: String
    /// Surowy bundle ID z AX stacking identifier (przed heurystyką).
    let axDeliveringBundleID: String?
    /// Etykiety ikon z AXImage (np. „WhatsApp”, „Wiadomości”) — najpewniejsze źródło ikony.
    let iconLabels: [String]
    let appName: String
    let title: String
    let body: String
    let isCall: Bool
    /// True gdy nadawcę potwierdza AX stacking identifier — nie tylko heurystyka tekstowa.
    let hasTrustedSource: Bool
    let answerButton: AXUIElement?
    let declineButton: AXUIElement?
    /// Przyciski akcji w banerze (Odbierz/Odrzuć) — połączenia często bez etykiet AX.
    let actionButtonCount: Int
    let hasAnswerControl: Bool
    let hasDeclineControl: Bool
    /// Pole odpowiedzi w banerze NC (gdy dostępne).
    let replyField: AXUIElement?
    /// Przycisk „Odpowiedz” / „Wyślij” w banerze NC.
    let replyButton: AXUIElement?
    /// Element banera — pozwala zamknąć systemowy dymek po pokazaniu w notchu.
    let element: AXUIElement?

    var appBundleID: String { deliveringBundleID }

    var supportsQuickReply: Bool {
        replyField != nil || replyButton != nil
    }

    var isLikelyCall: Bool {
        // `isCall` is already scored at parse time with raw AX text; don't let display-title
        // scrubbing (e.g. "Powiadomienie") drop a known call below threshold.
        if isCall { return true }
        return NotificationAppCatalog.isLikelyIncomingCallBanner(
            title: title,
            body: body,
            iconLabels: iconLabels,
            axDeliveringBundleID: axDeliveringBundleID,
            actionButtonCount: actionButtonCount,
            hasAnswerControl: hasAnswerControl,
            hasDeclineControl: hasDeclineControl,
            isCallFlag: false
        )
    }

    var fingerprint: String {
        "\(deliveringBundleID)|\(serviceBundleID)|\(title)|\(body)"
    }
}

@MainActor
final class NotificationCenterObserver {
    private static let logger = Logger(subsystem: NotchFlowConstants.bundleID, category: "NotificationCenter")

    var onBannerDetected: ((ParsedNotificationBanner) -> Void)?
    var onScanComplete: (([ParsedNotificationBanner]) -> Void)?

    private var pollTask: Task<Void, Never>?
    private var isEnabled = false
    /// Szybki tryb skanowania — połączenia: event-first + wolny safety poll.
    private var callsPriorityScanning = false
    /// Gdy CallManager ma ringing/active — częstszy safety poll.
    var callSessionActiveProvider: (() -> Bool)?
    /// True tylko gdy w notchu wisi połączenie przychodzące (dzwoni teraz).
    var incomingCallRingingProvider: (() -> Bool)?
    /// Nazwa dzwoniącego już ustalona w bieżącej sesji (incoming/active) — pozwala
    /// pominąć kosztowne scrape'y AX/OCR w kolejnych skanach.
    var knownCallerNameProvider: (() -> String?)?
    private var seenFingerprints: [String: Date] = [:]
    private var consecutiveEmptyScans = 0
    private var axObservers: [pid_t: AXObserver] = [:]
    private var eventScanTask: Task<Void, Never>?
    private var coalesceScanTask: Task<Void, Never>?
    private var scanInFlight = false
    private var scanPending = false

    private static let axMaxDepth = 10
    private static let axMaxNodesPerPID = 1_000

    /// Temporary file trace for Continuity / Phone.app call detection.
    private static func callDebugTrace(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
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

    private var pollInterval: Duration {
        // Banners are nested AXGroups inside an existing NC window — AXObserver on the
        // app element often misses them, so keep polling tight enough to catch short toasts.
        if callsPriorityScanning, callSessionActiveProvider?() == true {
            return .milliseconds(700)
        }
        if consecutiveEmptyScans < 8 {
            return .milliseconds(900)
        }
        if consecutiveEmptyScans < 20 {
            return .milliseconds(1_500)
        }
        return .seconds(2)
    }

    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    func setEnabled(_ enabled: Bool, callsPriority: Bool = false) {
        isEnabled = enabled
        callsPriorityScanning = enabled && callsPriority
        if enabled {
            consecutiveEmptyScans = 0
            startPolling()
            Task { await self.scanForBanners() }
        } else {
            pollTask?.cancel()
            pollTask = nil
            eventScanTask?.cancel()
            eventScanTask = nil
            coalesceScanTask?.cancel()
            coalesceScanTask = nil
            removeAXObservers()
            consecutiveEmptyScans = 0
            callsPriorityScanning = false
            scanInFlight = false
            scanPending = false
        }
    }

    func requestPermission() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    func pressAnswer(on banner: ParsedNotificationBanner) -> Bool {
        // Lift cover so Continuity receives the click.
        ContinuityCallBannerCover.stopCovering()
        if let button = banner.answerButton, AXHelpers.press(button) {
            Self.callDebugTrace("answer via banner.answerButton")
            return true
        }
        if let element = banner.element,
           let button = Self.findButton(in: element, matching: Self.answerKeywords),
           AXHelpers.press(button) {
            Self.callDebugTrace("answer via banner AX keywords")
            return true
        }
        let ok = ContinuityCallActions.pressAnswer()
        Self.callDebugTrace("answer via ContinuityCallActions=\(ok)")
        return ok
    }

    @discardableResult
    func pressDecline(on banner: ParsedNotificationBanner) -> Bool {
        ContinuityCallBannerCover.stopCovering()
        if let button = banner.declineButton, AXHelpers.press(button) {
            return true
        }
        if let element = banner.element,
           let button = Self.findButton(in: element, matching: Self.declineKeywords),
           AXHelpers.press(button) {
            return true
        }
        return ContinuityCallActions.pressDecline()
    }

    /// Zamyka systemowy dymek (akcja „Close” przez AX) — powiadomienie zostało już pokazane w notchu.
    /// Ponawia próby, bo w trakcie animacji wjazdu akcja „Close” bywa jeszcze niedostępna.
    func dismissBanner(_ banner: ParsedNotificationBanner) {
        guard let element = banner.element else { return }
        Task { @MainActor in
            for attempt in 0..<8 {
                if dismissAXElement(element) {
                    return
                }
                try? await Task.sleep(for: .milliseconds(attempt == 0 ? 120 : 180))
            }
            Self.logger.debug("dismissBanner: close action not found for \(banner.title, privacy: .private)")
        }
    }

    /// Hide Continuity / NC call UI that duplicates the notch — once per ring.
    /// Continuity's photo card has no Close action, so we cover it with an opaque panel.
    func dismissVisibleCallSystemBanners(from banners: [ParsedNotificationBanner]) {
        guard !didHideSystemCallUIThisRing else { return }
        didHideSystemCallUIThisRing = true
        Task { @MainActor in
            var closed = 0
            for banner in banners where banner.isLikelyCall {
                guard let element = banner.element else { continue }
                if dismissAXElement(element) { closed += 1 }
            }
            ContinuityCallBannerCover.startCovering()
            Self.callDebugTrace("hid system call UI ncClose=\(closed) cover=started")
        }
    }

    func resetSystemCallUIHideState() {
        didHideSystemCallUIThisRing = false
        ContinuityCallBannerCover.stopCovering()
    }

    private var didHideSystemCallUIThisRing = false

    private func dismissAXElement(_ element: AXUIElement) -> Bool {
        if AXHelpers.performCloseAction(on: element) { return true }
        if let close = Self.findButton(in: element, matching: Self.closeBannerKeywords),
           AXHelpers.press(close) {
            return true
        }
        return false
    }

    private static let closeBannerKeywords = [
        "close", "clear", "dismiss",
        "zamknij", "wyczyść", "usuń",
        "schließen", "chiudi", "cerrar",
    ]

    /// Best-effort quick reply via AX text field / Reply button on the live NC banner.
    @discardableResult
    func sendReply(on banner: ParsedNotificationBanner, text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if let field = banner.replyField ?? (banner.element.flatMap { Self.findTextField(in: $0) }) {
            _ = AXHelpers.focused(field)
            if AXHelpers.setValue(trimmed, on: field) {
                if let send = banner.replyButton
                    ?? Self.findButton(in: banner.element ?? field, matching: Self.sendKeywords)
                    ?? Self.findButton(in: banner.element ?? field, matching: Self.replyKeywords) {
                    return AXHelpers.press(send)
                }
                // Some banners submit on Return via the focused field's default action.
                return AXHelpers.press(field)
            }
        }

        if let reply = banner.replyButton
            ?? (banner.element.flatMap { Self.findButton(in: $0, matching: Self.replyKeywords) }) {
            // Reveal the inline field, then try again once.
            guard AXHelpers.press(reply), let element = banner.element else { return false }
            if let field = Self.findTextField(in: element) {
                _ = AXHelpers.focused(field)
                if AXHelpers.setValue(trimmed, on: field) {
                    if let send = Self.findButton(in: element, matching: Self.sendKeywords) {
                        return AXHelpers.press(send)
                    }
                    return AXHelpers.press(field)
                }
            }
            return true
        }

        return false
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                await scanForBanners()
                try? await Task.sleep(for: pollInterval)
            }
        }
    }

    // MARK: - Event-driven detection

    /// Banery wykrywamy natychmiast po utworzeniu okna w Notification Center (AXObserver),
    /// a polling zostaje jako fallback — dzięki temu dymek można zamknąć podczas animacji wjazdu.
    private func installAXObserversIfNeeded(pids: [pid_t]) {
        for pid in pids {
            installAXObserverIfNeeded(pid: pid)
        }
    }

    private func installAXObserverIfNeeded(pid: pid_t) {
        let observer: AXObserver
        if let existing = axObservers[pid] {
            observer = existing
        } else {
            var created: AXObserver?
            let callback: AXObserverCallback = { _, _, _, refcon in
                guard let refcon else { return }
                let instance = Unmanaged<NotificationCenterObserver>.fromOpaque(refcon).takeUnretainedValue()
                Task { @MainActor in
                    instance.handleAXEvent()
                }
            }
            guard AXObserverCreate(pid, callback, &created) == .success, let created else {
                Self.logger.debug("AXObserverCreate failed for pid \(pid)")
                return
            }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
            axObservers[pid] = created
            observer = created
        }

        let appElement = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let notifications = [
            kAXWindowCreatedNotification,
            kAXCreatedNotification,
            kAXUIElementDestroyedNotification,
            kAXLayoutChangedNotification,
        ]

        for notification in notifications {
            _ = AXObserverAddNotification(observer, appElement, notification as CFString, refcon)
        }

        // Toast groups are created under existing windows — observe each window too.
        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let windows = windowsRef as? [AXUIElement] {
            for window in windows {
                for notification in notifications {
                    _ = AXObserverAddNotification(observer, window, notification as CFString, refcon)
                }
            }
        }
    }

    private func removeAXObservers() {
        for observer in axObservers.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        axObservers.removeAll()
    }

    private func handleAXEvent() {
        guard isEnabled else { return }
        // Nested banner groups often need a short burst — first AX tick can be empty.
        scheduleBurstScans()
    }

    /// Jedno oczekujące skanowanie — coalescing jak w notchify MediaMonitor.
    private func requestScan(coalesceMilliseconds: Int = 100) {
        scanPending = true
        guard coalesceScanTask == nil else { return }
        coalesceScanTask = Task { @MainActor in
            defer { coalesceScanTask = nil }
            if coalesceMilliseconds > 0 {
                try? await Task.sleep(for: .milliseconds(coalesceMilliseconds))
            }
            guard !Task.isCancelled else { return }
            while scanPending {
                scanPending = false
                await scanForBanners()
            }
        }
    }

    private func scheduleDelayedScan(milliseconds: Int) {
        requestScan(coalesceMilliseconds: milliseconds)
    }

    /// Połączenia: krótki burst tylko po AX event (baner często pusty w pierwszych ms).
    private func scheduleBurstScans() {
        eventScanTask?.cancel()
        eventScanTask = Task { @MainActor in
            defer { eventScanTask = nil }
            var lastDelay = 0
            for delay in [0, 150, 400, 800] {
                let delta = delay - lastDelay
                if delta > 0 {
                    try? await Task.sleep(for: .milliseconds(delta))
                }
                lastDelay = delay
                guard !Task.isCancelled else { return }
                await scanForBanners()
            }
        }
    }

    private func scanForBanners() async {
        guard isEnabled, isAccessibilityTrusted else { return }
        if scanInFlight {
            scanPending = true
            return
        }
        scanInFlight = true
        defer { scanInFlight = false }

        let pids = AXHelpers.accessibilityBannerPIDs(callsPriority: callsPriorityScanning)
        guard !pids.isEmpty else { return }

        installAXObserversIfNeeded(pids: pids)

        var banners: [ParsedNotificationBanner] = []
        var seenKeys = Set<String>()
        var foundConfidentCall = false

        for pid in pids {
            if !callsPriorityScanning {
                guard notificationCenterMayHaveBanners(pid: pid) else { continue }
            }

            let hostBundleID = AXHelpers.bundleID(forPID: pid)
            let hostIsCallApp = NotificationAppCatalog.isCallUIHostBundleID(hostBundleID)

            let appElement = AXUIElementCreateApplication(pid)
            var nodeBudget = Self.axMaxNodesPerPID
            for banner in collectBanners(
                from: appElement,
                depth: 0,
                inheritedBundleHint: hostIsCallApp ? hostBundleID : nil,
                nodeBudget: &nodeBudget
            ) {
                let key = banner.fingerprint
                guard seenKeys.insert(key).inserted else { continue }
                banners.append(banner)
                if banner.isLikelyCall {
                    foundConfidentCall = true
                    Self.callDebugTrace(
                        "found call banner host=\(hostBundleID ?? "?") title=\(banner.title) buttons=\(banner.actionButtonCount)"
                    )
                }
            }
            // Don't stop after a privacy-scrubbed FACETIME stub — Phone.app may still expose the name.
            let hasUsableCaller = banners.contains {
                $0.isLikelyCall && NotificationAppCatalog.isPlausibleCallerName($0.title)
            }
            if hasUsableCaller, callsPriorityScanning { break }
        }

        if callsPriorityScanning {
            let hosts = pids.compactMap(AXHelpers.bundleID(forPID:))
            let hasCallHost = hosts.contains { NotificationAppCatalog.isCallUIHostBundleID($0) }
            // Deep scrapes read other apps' window titles / capture the screen — macOS
            // lights the screen-recording indicator for that, so run them only while a
            // call is actually ringing (call banner on screen or incoming call in notch).
            let ringingNow = banners.contains(where: \.isLikelyCall)
                || (hasCallHost && incomingCallRingingProvider?() == true)
            var callerHint = bestCallerHint(from: banners)
            // Once the ring session already has a usable name, don't re-scrape (AX
            // walks + OCR captures are the main source of in-ring lag).
            if callerHint == nil,
               let known = knownCallerNameProvider?(),
               NotificationAppCatalog.isPlausibleCallerName(known) {
                callerHint = known
            }
            if callerHint == nil, ringingNow {
                callerHint = scrapeCallerHintFromNotificationCenter()
                    ?? scrapeCallerFromCallHosts(pids: pids)
                    ?? scrapeCallerFromCallWindowTitles()
                if callerHint == nil {
                    callerHint = await scrapeCallerFromContinuityOverlayOCR()
                }
            }

            if let callerHint {
                Self.callDebugTrace("callerHint resolved=\(callerHint)")
            }

            for banner in banners {
                Self.callDebugTrace(
                    """
                    banner call=\(banner.isLikelyCall) isCall=\(banner.isCall) \
                    buttons=\(banner.actionButtonCount) answer=\(banner.hasAnswerControl) decline=\(banner.hasDeclineControl) \
                    deliver=\(banner.deliveringBundleID) ax=\(banner.axDeliveringBundleID ?? "nil") \
                    title=\(banner.title) body=\(banner.body) icons=\(banner.iconLabels.joined(separator: "|"))
                    """
                )
            }

            // Upgrade privacy stubs ("Powiadomienie" / FACETIME_NOTIFICATION) with a real caller hint.
            if let callerHint,
               NotificationAppCatalog.isPlausibleCallerName(callerHint),
               let idx = banners.firstIndex(where: {
                   $0.isLikelyCall && !NotificationAppCatalog.isPlausibleCallerName($0.title)
               }) {
                banners[idx] = forcingCallBanner(
                    banners[idx],
                    appBundleID: NotificationAppCatalog.isCallUIHostBundleID(banners[idx].deliveringBundleID)
                        ? banners[idx].deliveringBundleID
                        : "com.apple.mobilephone",
                    callerHint: callerHint
                )
                foundConfidentCall = true
                Self.callDebugTrace("enriched call banner title=\(banners[idx].title)")
            }

            // Tahoe: Phone.app / FaceTime host the ring UI; AX toast often has no call keywords.
            if !foundConfidentCall, hasCallHost,
               let synthetic = synthesizeCallBanner(
                fromCallHostPIDs: pids,
                callerHint: callerHint
               ) {
                banners.insert(synthetic, at: 0)
                foundConfidentCall = true
                Self.callDebugTrace(
                    "synthesized call from host title=\(synthetic.title) app=\(synthetic.deliveringBundleID) buttons=\(synthetic.actionButtonCount)"
                )
            } else if !foundConfidentCall, hasCallHost, let boosted = banners.first {
                let forced = forcingCallBanner(
                    boosted,
                    appBundleID: "com.apple.mobilephone",
                    callerHint: callerHint
                )
                banners[0] = forced
                foundConfidentCall = true
                Self.callDebugTrace("boosted NC banner to call title=\(forced.title)")
            } else if foundConfidentCall, hasCallHost,
                      !banners.contains(where: {
                          $0.isLikelyCall && NotificationAppCatalog.isPlausibleCallerName($0.title)
                      }),
                      let synthetic = synthesizeCallBanner(
                        fromCallHostPIDs: pids,
                        callerHint: callerHint
                      ),
                      NotificationAppCatalog.isPlausibleCallerName(synthetic.title) {
                banners.insert(synthetic, at: 0)
                Self.callDebugTrace(
                    "synthesized richer call title=\(synthetic.title) app=\(synthetic.deliveringBundleID)"
                )
            }

            if !banners.isEmpty || hasCallHost {
                Self.callDebugTrace(
                    "scan pids=\(pids.count) banners=\(banners.count) calls=\(banners.filter(\.isLikelyCall).count) hosts=\(hosts.joined(separator: ",")) callerHint=\(callerHint ?? "nil")"
                )
            }
        }

        if callsPriorityScanning {
            banners.sort { callBannerPriority($0) > callBannerPriority($1) }
        }

        if banners.isEmpty {
            consecutiveEmptyScans += 1
        } else {
            consecutiveEmptyScans = 0
        }

        let now = Date()
        seenFingerprints = seenFingerprints.filter { now.timeIntervalSince($0.value) < 30 }

        for banner in banners {
            if banner.isLikelyCall {
                seenFingerprints[banner.fingerprint] = now
                onBannerDetected?(banner)
                continue
            }
            let alreadySeen = seenFingerprints.keys.contains(banner.fingerprint)
            guard !alreadySeen else { continue }
            seenFingerprints[banner.fingerprint] = now
            onBannerDetected?(banner)
        }

        onScanComplete?(banners)
    }

    private func callBannerPriority(_ banner: ParsedNotificationBanner) -> Int {
        NotificationAppCatalog.incomingCallScore(
            title: banner.title,
            body: banner.body,
            iconLabels: banner.iconLabels,
            axDeliveringBundleID: banner.axDeliveringBundleID,
            actionButtonCount: banner.actionButtonCount,
            hasAnswerControl: banner.hasAnswerControl,
            hasDeclineControl: banner.hasDeclineControl,
            isCallFlag: banner.isCall
        )
    }

    /// Phone.app / FaceTime often expose a window without NC banner subrole or call keywords.
    private func synthesizeCallBanner(
        fromCallHostPIDs pids: [pid_t],
        callerHint: String?
    ) -> ParsedNotificationBanner? {
        for pid in pids {
            guard let hostBundleID = AXHelpers.bundleID(forPID: pid),
                  NotificationAppCatalog.isCallUIHostBundleID(hostBundleID) else { continue }
            let canonical = NotificationAppCatalog.canonicalBundleID(for: hostBundleID)

            let appElement = AXUIElementCreateApplication(pid)
            let windows = AXHelpers.children(of: appElement).filter {
                let role = AXHelpers.role(of: $0) ?? ""
                return (role == "AXWindow" || role == "AXGroup") && !AXHelpers.isHidden($0)
            }
            let window = windows.first {
                (AXHelpers.role(of: $0) ?? "") == "AXWindow"
            } ?? windows.first {
                guard let frame = AXHelpers.frame(of: $0) else { return false }
                return frame.width >= 160 && frame.height >= 60
            }
            enableAXManualAccessibility(on: appElement)

            guard let window else {
                // Even without a window role, walk the app tree for Continuity caller text.
                if let fromTree = scrapeCallerFromAXTree(appElement, host: hostBundleID)
                    ?? usableCaller(callerHint) {
                    Self.callDebugTrace("call host \(hostBundleID) process-only with caller=\(fromTree)")
                    return ParsedNotificationBanner(
                        deliveringBundleID: canonical,
                        serviceBundleID: canonical,
                        axDeliveringBundleID: hostBundleID,
                        iconLabels: [NotificationAppCatalog.name(for: canonical)],
                        appName: NotificationAppCatalog.name(for: canonical),
                        title: fromTree,
                        body: "process-only-ring",
                        isCall: true,
                        hasTrustedSource: true,
                        answerButton: nil,
                        declineButton: nil,
                        actionButtonCount: 0,
                        hasAnswerControl: false,
                        hasDeclineControl: false,
                        replyField: nil,
                        replyButton: nil,
                        element: nil
                    )
                }
                Self.callDebugTrace("call host \(hostBundleID) has no usable AX chrome — process-only ring")
                let title = usableCaller(callerHint) ?? loc("Incoming call")
                // No fake Answer/Decline — otherwise we never promote to the in-call state.
                return ParsedNotificationBanner(
                    deliveringBundleID: canonical,
                    serviceBundleID: canonical,
                    axDeliveringBundleID: hostBundleID,
                    iconLabels: [NotificationAppCatalog.name(for: canonical)],
                    appName: NotificationAppCatalog.name(for: canonical),
                    title: title,
                    body: "process-only-ring",
                    isCall: true,
                    hasTrustedSource: true,
                    answerButton: nil,
                    declineButton: nil,
                    actionButtonCount: 0,
                    hasAnswerControl: false,
                    hasDeclineControl: false,
                    replyField: nil,
                    replyButton: nil,
                    element: nil
                )
            }

            dumpCallHostAX(window, host: hostBundleID)

            enableAXManualAccessibility(on: window)
            let buttons = collectButtons(from: window)
            let texts = collectText(from: window, depth: 0)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !NotificationAppCatalog.isInternalAccessibilityLabel($0) }
            let caller = usableCaller(callerHint)
                ?? scrapeCallerFromAXTree(window, host: hostBundleID)
                ?? usableCaller(
                    NotificationAppCatalog.bestCallerName(
                        from: texts,
                        appName: NotificationAppCatalog.name(for: canonical)
                    )
                )
                ?? loc("Incoming call")
            let answer = buttons.first { isAnswerButton($0) }
                ?? Self.findButton(in: window, matching: Self.answerKeywords)
            let decline = buttons.first { isDeclineButton($0) }
                ?? Self.findButton(in: window, matching: Self.declineKeywords)
            var answerButton = answer
            var declineButton = decline
            if answerButton == nil, declineButton == nil, buttons.count >= 2 {
                declineButton = buttons[0]
                answerButton = buttons[buttons.count - 1]
            }

            return ParsedNotificationBanner(
                deliveringBundleID: canonical,
                serviceBundleID: canonical,
                axDeliveringBundleID: hostBundleID,
                iconLabels: [NotificationAppCatalog.name(for: canonical)],
                appName: NotificationAppCatalog.name(for: canonical),
                title: caller,
                body: texts.filter { $0 != caller }.prefix(2).joined(separator: " · "),
                isCall: true,
                hasTrustedSource: true,
                answerButton: answerButton,
                declineButton: declineButton,
                actionButtonCount: max(buttons.count, 2),
                hasAnswerControl: answerButton != nil || buttons.count >= 2,
                hasDeclineControl: declineButton != nil || buttons.count >= 2,
                replyField: nil,
                replyButton: nil,
                element: window
            )
        }
        return nil
    }

    private func forcingCallBanner(
        _ banner: ParsedNotificationBanner,
        appBundleID: String,
        callerHint: String?
    ) -> ParsedNotificationBanner {
        let canonical = NotificationAppCatalog.canonicalBundleID(for: appBundleID)
        let title = usableCaller(callerHint)
            ?? usableCaller(banner.title)
            ?? usableCaller(banner.body)
            ?? loc("Incoming call")
        return ParsedNotificationBanner(
            deliveringBundleID: canonical,
            serviceBundleID: canonical,
            axDeliveringBundleID: banner.axDeliveringBundleID ?? appBundleID,
            iconLabels: banner.iconLabels.isEmpty
                ? [NotificationAppCatalog.name(for: canonical)]
                : banner.iconLabels,
            appName: NotificationAppCatalog.name(for: canonical),
            title: title,
            body: banner.body == title ? "" : banner.body,
            isCall: true,
            hasTrustedSource: true,
            answerButton: banner.answerButton,
            declineButton: banner.declineButton,
            actionButtonCount: banner.actionButtonCount,
            hasAnswerControl: banner.hasAnswerControl || banner.answerButton != nil,
            hasDeclineControl: banner.hasDeclineControl || banner.declineButton != nil,
            replyField: nil,
            replyButton: nil,
            element: banner.element
        )
    }

    private func bestCallerHint(from banners: [ParsedNotificationBanner]) -> String? {
        // Prefer call-adjacent strings ("Ada, Połączenie przychodzące") over raw NC titles.
        // Calendar Up Next ("NIEDZIELA") must never become the caller hint.
        for banner in banners {
            if let fromAttr = callerFromCallLikeText(
                [banner.title, banner.body].joined(separator: ", ")
            ) {
                return fromAttr
            }
        }
        for banner in banners where banner.isCall || banner.isLikelyCall {
            let lines = [banner.title]
                + banner.body.components(separatedBy: " · ")
                + banner.iconLabels
            let name = NotificationAppCatalog.bestCallerName(from: lines, appName: "")
            if let usable = usableCaller(name) { return usable }
        }
        return nil
    }

    /// Deep scrape NC for a contact-like string while Phone.app is ringing.
    private func scrapeCallerHintFromNotificationCenter() -> String? {
        let bundleIDs = [
            "com.apple.notificationcenterui",
            "com.apple.UserNotificationCenter",
        ]
        for bundleID in bundleIDs {
            guard let pid = AXHelpers.runningApplication(bundleID: bundleID)?.processIdentifier else {
                continue
            }
            let root = AXUIElementCreateApplication(pid)
            enableAXManualAccessibility(on: root)
            if let found = scrapeCallerFromAXTree(root, host: bundleID) {
                return found
            }
        }
        return nil
    }

    /// Phone.app Continuity banner often exposes the contact only after AXManualAccessibility.
    private func scrapeCallerFromCallHosts(pids: [pid_t]) -> String? {
        for pid in pids {
            guard let bundleID = AXHelpers.bundleID(forPID: pid),
                  NotificationAppCatalog.isCallUIHostBundleID(bundleID) else { continue }
            let root = AXUIElementCreateApplication(pid)
            enableAXManualAccessibility(on: root)
            if let found = scrapeCallerFromAXTree(root, host: bundleID) {
                return found
            }
        }
        return nil
    }

    /// Window titles sometimes carry the contact when AX children are empty.
    private func scrapeCallerFromCallWindowTitles() -> String? {
        guard let info = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        for window in info {
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  let bundleID = AXHelpers.bundleID(forPID: pid),
                  NotificationAppCatalog.isCallUIHostBundleID(bundleID)
                    || bundleID.contains("notificationcenter")
                    || bundleID == "com.apple.UserNotificationCenter"
            else { continue }

            let name = (window[kCGWindowName as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let usable = usableCaller(name) {
                Self.callDebugTrace("caller scrape (window title)=\(usable) host=\(bundleID)")
                return usable
            }
            if let fromCall = callerFromCallLikeText(name) {
                Self.callDebugTrace("caller scrape (window call-like)=\(fromCall) host=\(bundleID)")
                return fromCall
            }
        }
        return nil
    }

    private func enableAXManualAccessibility(on element: AXUIElement) {
        // SwiftUI call banners often hide static text until this is set.
        AXUIElementSetAttributeValue(
            element,
            "AXManualAccessibility" as CFString,
            kCFBooleanTrue
        )
        AXUIElementSetAttributeValue(
            element,
            "AXEnhancedUserInterface" as CFString,
            kCFBooleanTrue
        )
    }

    private func scrapeCallerFromAXTree(_ root: AXUIElement, host: String) -> String? {
        var budget = 320
        var orderedTexts: [String] = []
        var callAdjacent: [String] = []

        func walk(_ el: AXUIElement, depth: Int) {
            guard depth < 10, budget > 0 else { return }
            budget -= 1
            for value in [
                AXHelpers.attributedDescription(of: el),
                AXHelpers.title(of: el),
                AXHelpers.description(of: el),
                AXHelpers.label(of: el),
                AXHelpers.value(of: el),
            ].compactMap({ $0 }) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                orderedTexts.append(trimmed)
                if let caller = callerFromCallLikeText(trimmed) {
                    callAdjacent.append(caller)
                }
            }
            for child in AXHelpers.children(of: el) {
                walk(child, depth: depth + 1)
            }
        }
        walk(root, depth: 0)

        // Continuity layout first: "Martyna Tymków" then "Z Twojego iPhone'a".
        for index in orderedTexts.indices {
            guard NotificationAppCatalog.isContinuityCallSubtitle(orderedTexts[index]) else { continue }
            let before = orderedTexts[..<index].reversed()
            for candidate in before {
                if let usable = usableCaller(candidate) {
                    Self.callDebugTrace("caller scrape (continuity)=\(usable) host=\(host)")
                    return usable
                }
            }
        }

        // call-adjacent only after filtering Continuity audio-route chrome ("Mikrofon (iPhone…)").
        if let best = callAdjacent.first {
            Self.callDebugTrace("caller scrape (call-adjacent)=\(best) host=\(host)")
            return best
        }

        return nil
    }

    private var lastContinuityOCRAttemptAt: Date?
    private var lastWindowDumpAt: Date?
    private var lastScreenCaptureAccessRequestAt: Date?

    /// OCR the Continuity photo card — AX often exposes only audio routes, not the contact name.
    private func scrapeCallerFromContinuityOverlayOCR() async -> String? {
        if let last = lastContinuityOCRAttemptAt, Date().timeIntervalSince(last) < 0.8 {
            return nil
        }
        lastContinuityOCRAttemptAt = .now

        // Rebuilding the app resets the Screen Recording grant — without it the card
        // can't be located at all, so re-request up front (prompt shows at most once).
        if !CGPreflightScreenCaptureAccess() {
            if lastScreenCaptureAccessRequestAt == nil
                || Date().timeIntervalSince(lastScreenCaptureAccessRequestAt!) > 30 {
                lastScreenCaptureAccessRequestAt = .now
                let granted = CGRequestScreenCaptureAccess()
                Self.callDebugTrace("screen capture access requested granted=\(granted)")
            }
            return nil
        }

        if await ContinuityCallActions.findCard() == nil {
            // Periodic window dump so we can see what the card actually looks like to CG.
            if lastWindowDumpAt == nil || Date().timeIntervalSince(lastWindowDumpAt!) > 10 {
                lastWindowDumpAt = .now
                Self.callDebugTrace(
                    "ocr miss — no card; screenRec=\(CGPreflightScreenCaptureAccess()) windows: "
                        + ContinuityCallActions.debugWindowSummary()
                )
            }
            return nil
        }
        if let name = await ContinuityCallActions.ocrCallerName() {
            Self.callDebugTrace("caller scrape (ocr)=\(name)")
            return name
        }
        if !CGPreflightScreenCaptureAccess() {
            Self.callDebugTrace("ocr waiting for Screen Recording permission")
        } else {
            Self.callDebugTrace("ocr miss — empty / unreadable card")
        }
        return nil
    }

    /// "Anna Kowalska, Połączenie przychodzące" / "Ada, mobile" → "Anna Kowalska".
    private func callerFromCallLikeText(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if NotificationAppCatalog.isContinuityDeviceRouteLabel(trimmed) { return nil }
        let lower = trimmed.lowercased()
        // Bare "iphone" matches Continuity mic/camera routes — require stronger call marks.
        let callMarks = [
            "połączenie", "przychodzące", "incoming", "facetime", "mobile",
            "calling", "ringing", "telefon", "anruf", "chiamata", "llamada",
            "facetime_notification", "from your iphone", "z twojego iphone",
        ]
        guard callMarks.contains(where: { lower.contains($0) }) else { return nil }

        let separators = CharacterSet(charactersIn: ",·\n—–-")
        let parts = trimmed.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for part in parts {
            if let usable = usableCaller(part) { return usable }
        }
        return nil
    }

    /// Walk nested AX nodes under a FaceTime/Phone toast for a contact-like label.
    private func deepCallerName(from element: AXUIElement) -> String? {
        var budget = 120
        var candidates: [String] = []

        func walk(_ el: AXUIElement, depth: Int) {
            guard depth < 8, budget > 0 else { return }
            budget -= 1
            for value in [
                AXHelpers.title(of: el),
                AXHelpers.description(of: el),
                AXHelpers.label(of: el),
                AXHelpers.value(of: el),
                AXHelpers.attributedDescription(of: el),
                AXHelpers.help(of: el),
            ].compactMap({ $0 }) {
                if let fromCall = callerFromCallLikeText(value) {
                    candidates.append(fromCall)
                }
                for part in value.components(separatedBy: CharacterSet(charactersIn: ",·\n|")) {
                    if let usable = usableCaller(part) {
                        candidates.append(usable)
                    }
                }
            }
            // Also try identifier — sometimes stacking embeds a display name nearby.
            if let ident = AXHelpers.identifier(of: el), !ident.uppercased().contains("FACETIME") {
                if let usable = usableCaller(ident) {
                    candidates.append(usable)
                }
            }
            for child in AXHelpers.children(of: el) {
                walk(child, depth: depth + 1)
            }
        }

        walk(element, depth: 0)
        if candidates.isEmpty {
            Self.callDebugTrace("deep caller miss — dumping AX")
            dumpCallHostAX(element, host: "facetime-toast")
        }
        return candidates.first
    }

    private func usableCaller(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard NotificationAppCatalog.isPlausibleCallerName(trimmed) else { return nil }
        // Extra FaceTime chrome tokens.
        let lower = trimmed.lowercased()
        if lower == "facetime_notification" || lower.hasPrefix("facetime_") { return nil }
        return trimmed
    }

    private func dumpCallHostAX(_ element: AXUIElement, host: String, depth: Int = 0) {
        guard depth == 0 else { return }
        var lines: [String] = ["ax-dump host=\(host)"]
        func walk(_ el: AXUIElement, d: Int, budget: inout Int) {
            guard d < 5, budget > 0 else { return }
            budget -= 1
            let role = AXHelpers.role(of: el) ?? "?"
            let title = AXHelpers.title(of: el) ?? ""
            let desc = AXHelpers.description(of: el) ?? ""
            let attr = AXHelpers.attributedDescription(of: el) ?? ""
            let sub = AXHelpers.subrole(of: el) ?? ""
            if d <= 2 || role.contains("Button") || !title.isEmpty || !desc.isEmpty || !attr.isEmpty {
                lines.append(
                    String(repeating: " ", count: d * 2)
                        + "\(role) sub=\(sub) title=\(title.prefix(60)) desc=\(desc.prefix(40)) attr=\(attr.prefix(80))"
                )
            }
            for child in AXHelpers.children(of: el) {
                walk(child, d: d + 1, budget: &budget)
            }
        }
        var budget = 80
        walk(element, d: 0, budget: &budget)
        Self.callDebugTrace(lines.joined(separator: " | "))
    }

    private func notificationCenterMayHaveBanners(pid: pid_t) -> Bool {
        let appElement = AXUIElementCreateApplication(pid)
        for child in AXHelpers.children(of: appElement) {
            if AXHelpers.isHidden(child) { continue }
            // Tahoe hosts toasts inside a full-screen AXSystemDialog ("Notification Center").
            if AXHelpers.subrole(of: child) == "AXSystemDialog" {
                return true
            }
            let title = (AXHelpers.title(of: child) ?? "").lowercased()
            if title.contains("notification") || title.contains("powiadom") {
                return true
            }
            guard let frame = AXHelpers.frame(of: child) else { continue }
            if frame.width >= 180, frame.height >= 36, frame.height <= 360 {
                return true
            }
            if callsPriorityScanning, frame.width >= 80, frame.height >= 28, frame.height <= 400 {
                return true
            }
        }
        return callsPriorityScanning
    }

    private func collectBanners(
        from element: AXUIElement,
        depth: Int,
        inheritedBundleHint: String? = nil,
        nodeBudget: inout Int
    ) -> [ParsedNotificationBanner] {
        guard depth < Self.axMaxDepth, nodeBudget > 0 else { return [] }
        nodeBudget -= 1

        let bundleHint = deliveringBundleHint(for: element, inherited: inheritedBundleHint)

        var results: [ParsedNotificationBanner] = []
        let isNCBanner = AXHelpers.isNotificationCenterBanner(element)
        if let parsed = parseBanner(element, deliveringBundleHint: bundleHint) {
            results.append(parsed)
            // Banner groups already contain title/body — don't re-parse their static texts.
            if isNCBanner || (callsPriorityScanning && parsed.isLikelyCall) {
                return results
            }
        }

        for child in AXHelpers.children(of: element) {
            if AXHelpers.isHidden(child) { continue }
            guard nodeBudget > 0 else { break }
            results.append(
                contentsOf: collectBanners(
                    from: child,
                    depth: depth + 1,
                    inheritedBundleHint: bundleHint,
                    nodeBudget: &nodeBudget
                )
            )
            // Keep scanning siblings until we have a call banner with a real caller name.
            if callsPriorityScanning,
               results.contains(where: {
                   $0.isLikelyCall && NotificationAppCatalog.isPlausibleCallerName($0.title)
               }) {
                break
            }
        }

        return results
    }

    /// Szuka bundle ID w łańcuchu rodziców (stacking identifier bywa na oknie banera, nie na grupie wewnętrznej).
    private func deliveringBundleHint(for element: AXUIElement, inherited: String?) -> String? {
        var current: AXUIElement? = element
        var depth = 0
        while let el = current, depth < 8 {
            if let bundleID = Self.bundleID(fromStackingIdentifier: AXHelpers.stackingIdentifier(of: el)) {
                return bundleID
            }
            if let bundleID = Self.bundleID(fromStackingIdentifier: AXHelpers.identifier(of: el)) {
                return bundleID
            }
            current = AXHelpers.parent(of: el)
            depth += 1
        }
        return inherited
    }

    static func bundleID(fromStackingIdentifier identifier: String?) -> String? {
        NotificationAppCatalog.bundleID(fromStackingIdentifier: identifier)
    }

    private func parseBanner(_ element: AXUIElement, deliveringBundleHint: String?) -> ParsedNotificationBanner? {
        guard let frame = AXHelpers.frame(of: element) else { return nil }

        let buttons = collectButtons(from: element)
        let buttonCount = buttons.count
        let hostIsCallApp = NotificationAppCatalog.callBundleIDs.contains(
            NotificationAppCatalog.canonicalBundleID(for: deliveringBundleHint ?? "")
        ) || NotificationAppCatalog.isCallRelatedBundleHint(deliveringBundleHint)
        let callShape = buttonCount >= 2
        let isNCBanner = AXHelpers.isNotificationCenterBanner(element)

        let minWidth: CGFloat = (callShape || isNCBanner) ? 60 : 180
        let minHeight: CGFloat = (callShape || isNCBanner) ? 24 : 36
        guard frame.width >= minWidth, frame.height >= minHeight else { return nil }

        let role = AXHelpers.role(of: element) ?? ""
        let allowedRoles = [
            "AXWindow", "AXGroup", "AXScrollArea", "AXSheet", "AXPopover", "AXToolbar",
            "AXLayoutArea", "AXList", "AXRow", "AXCell", "AXStaticText",
        ]
        if !callShape && !isNCBanner {
            guard allowedRoles.contains(role) else { return nil }
        } else if role == "AXApplication" || role == "AXSystemWide" {
            return nil
        }

        let structured = collectStructuredBannerFields(from: element)
        let attributedParts = Self.attributedDescriptionParts(from: element)
        let parts = collectTextParts(from: element, depth: 0)
        var iconLabels = parts.icons + parts.others.filter { NotificationAppCatalog.isExactAppName($0) }
        // App name often lives only in AXAttributedDescription ("Signal, Alice, …").
        if let appToken = attributedParts.first, NotificationAppCatalog.isExactAppName(appToken) {
            if !iconLabels.contains(where: { $0.caseInsensitiveCompare(appToken) == .orderedSame }) {
                iconLabels.append(appToken)
            }
        }
        if let appName = structured.appName, NotificationAppCatalog.isExactAppName(appName) {
            if !iconLabels.contains(where: { $0.caseInsensitiveCompare(appName) == .orderedSame }) {
                iconLabels.append(appName)
            }
        }

        var contentCandidates = parts.others
        for field in [structured.title, structured.subtitle, structured.body].compactMap({ $0 }) {
            if !contentCandidates.contains(field) {
                contentCandidates.append(field)
            }
        }
        // Skip leading app-name token from attributed description when present.
        let attributedContent: [String]
        if let first = attributedParts.first, NotificationAppCatalog.isExactAppName(first) {
            attributedContent = Array(attributedParts.dropFirst())
        } else {
            attributedContent = attributedParts
        }
        for part in attributedContent where !contentCandidates.contains(part) {
            contentCandidates.append(part)
        }

        let texts = iconLabels + contentCandidates
        guard !texts.isEmpty || callShape || isNCBanner else { return nil }

        let buttonTitles = buttons.compactMap { buttonAccessibilityText($0) }.filter { !$0.isEmpty }

        let resolved = NotificationAppCatalog.resolve(
            iconTexts: iconLabels,
            contentTexts: contentCandidates,
            deliveringHint: deliveringBundleHint
        )
        let contentTexts = contentCandidates.filter { text in
            let lower = text.lowercased()
            if lower == "notification center" { return false }
            if NotificationAppCatalog.isExactAppName(text) { return false }
            if NotificationAppCatalog.isInternalAccessibilityLabel(text) { return false }
            return true
        }
        // Surowy tekst do scoringu — NIE odfiltrowywać „Połączenie przychodzące”
        // (isSystemCallUILabel), bo wtedy keyword znika i Continuity nie przechodzi progu.
        let scoreTitle = structured.title ?? contentTexts.first ?? resolved.displayName
        let scoreBody = structured.body
            ?? structured.subtitle
            ?? contentTexts.dropFirst().joined(separator: " · ")

        let callerLines = contentTexts.filter { !NotificationAppCatalog.isSystemCallUILabel($0) }
        var title = structured.title
            ?? NotificationAppCatalog.bestCallerName(
                from: callerLines.isEmpty ? contentTexts : callerLines,
                appName: resolved.displayName
            )
        var body = structured.body
            ?? contentTexts
                .filter { $0 != title && !NotificationAppCatalog.isSystemCallUILabel($0) }
                .joined(separator: " · ")
        if let subtitle = structured.subtitle,
           body.isEmpty || body == title,
           subtitle != title {
            body = subtitle
        }
        if title.isEmpty, callShape || isNCBanner {
            title = resolved.displayName
        }

        // Continuity often packs "Ada Nowak, Połączenie przychodzące" only in attributed description.
        if let attr = AXHelpers.attributedDescription(of: element),
           let caller = callerFromCallLikeText(attr) {
            title = caller
        } else if let caller = callerFromCallLikeText(attributedParts.joined(separator: ", ")) {
            title = caller
        } else if let caller = contentTexts.compactMap(usableCaller).first {
            title = caller
        }

        let looksLikeFaceTimeToast = texts.contains {
            $0.localizedCaseInsensitiveContains("FACETIME_NOTIFICATION")
                || $0.localizedCaseInsensitiveContains("facetime")
        } || (deliveringBundleHint?.localizedCaseInsensitiveContains("facetime") == true)
            || hostIsCallApp

        let hasAnswerControl = buttons.contains { isAnswerButton($0) }
            || Self.findButton(in: element, matching: Self.answerKeywords) != nil
        let hasDeclineControl = buttons.contains { isDeclineButton($0) }
            || Self.findButton(in: element, matching: Self.declineKeywords) != nil

        let strongEvidence = isCallBanner(
            deliveringBundleID: resolved.delivering,
            serviceBundleID: resolved.service,
            axDeliveringBundleID: deliveringBundleHint,
            iconLabels: iconLabels,
            texts: texts,
            buttons: buttonTitles,
            actionButtonCount: buttonCount,
            hasAnswerControl: hasAnswerControl,
            hasDeclineControl: hasDeclineControl
        )

        let callScore = NotificationAppCatalog.incomingCallScore(
            title: scoreTitle,
            body: scoreBody.isEmpty ? scoreTitle : scoreBody,
            iconLabels: iconLabels,
            axDeliveringBundleID: deliveringBundleHint,
            actionButtonCount: buttonCount,
            hasAnswerControl: hasAnswerControl,
            hasDeclineControl: hasDeclineControl,
            isCallFlag: strongEvidence
        )
        let isCall = callScore >= 3

        // Tahoe FaceTime/Phone banners often expose only "FACETIME_NOTIFICATION" / "Powiadomienie"
        // at the group root — the contact name lives on a nested static text.
        // Never deep-walk mere multi-button chrome (Calendar Up Next → "19 LIPCA").
        if looksLikeFaceTimeToast || isCall || hostIsCallApp {
            if !NotificationAppCatalog.isPlausibleCallerName(title),
               let deep = deepCallerName(from: element) {
                title = deep
                Self.callDebugTrace("deep caller from AX=\(deep)")
            }
        }

        if callsPriorityScanning, isCall || hostIsCallApp || looksLikeFaceTimeToast {
            let attr = AXHelpers.attributedDescription(of: element) ?? ""
            Self.callDebugTrace(
                """
                parse callScore=\(callScore) isCall=\(isCall) hostCall=\(hostIsCallApp) \
                title=\(title) scoreTitle=\(scoreTitle) attr=\(attr.prefix(120)) \
                texts=\(contentTexts.prefix(4).joined(separator: " | "))
                """
            )
        }

        // Phone.app / FaceTime incoming UI can be taller than a NC toast.
        let maxHeight: CGFloat = (isCall || hostIsCallApp) ? 720 : 280
        guard frame.height <= maxHeight else { return nil }

        var answerButton = buttons.first { isAnswerButton($0) }
            ?? (isCall ? Self.findButton(in: element, matching: Self.answerKeywords) : nil)
        var declineButton = buttons.first { isDeclineButton($0) }
            ?? (isCall ? Self.findButton(in: element, matching: Self.declineKeywords) : nil)
        if isCall, answerButton == nil, declineButton == nil, buttons.count >= 2 {
            declineButton = buttons[0]
            answerButton = buttons[buttons.count - 1]
        }

        let isKnownMessaging = NotificationAppCatalog.isMessagingApp(resolved.delivering)
            || NotificationAppCatalog.isMessagingApp(resolved.service)
            || NotificationAppCatalog.isEmailApp(resolved.delivering)
            || NotificationAppCatalog.isEmailApp(resolved.service)
        guard isCall || callShape || isNCBanner || !body.isEmpty || contentTexts.count >= 2
            || !title.isEmpty
            || isKnownMessaging else { return nil }

        // Privacy-scrubbed banners (esp. Signal) often have empty / generic AX text.
        // Keep a presence ping for known messaging/email apps.
        var displayTitle = title
        var displayBody = body.isEmpty ? title : body
        if !isCall,
           !NotificationAppCatalog.isReadableNotificationText(title: displayTitle, body: displayBody) {
            guard isKnownMessaging else { return nil }
            displayTitle = resolved.displayName
            displayBody = loc("New message")
        } else if !isCall, isKnownMessaging, displayBody.isEmpty || displayBody == displayTitle,
                  NotificationAppCatalog.isExactAppName(displayTitle)
                    || NotificationAppCatalog.isBlockedNotificationContent(title: displayTitle, body: "") {
            displayTitle = resolved.displayName
            displayBody = loc("New message")
        }

        let replyField = isCall ? nil : Self.findTextField(in: element)
        let replyButton = isCall
            ? nil
            : (Self.findButton(in: element, matching: Self.replyKeywords)
                ?? Self.findButton(in: element, matching: Self.sendKeywords))

        return ParsedNotificationBanner(
            deliveringBundleID: resolved.delivering,
            serviceBundleID: resolved.service,
            axDeliveringBundleID: deliveringBundleHint,
            iconLabels: iconLabels,
            appName: resolved.displayName,
            title: displayTitle,
            body: displayBody,
            isCall: isCall,
            hasTrustedSource: resolved.hasTrustedSource,
            answerButton: answerButton,
            declineButton: declineButton,
            actionButtonCount: buttonCount,
            hasAnswerControl: hasAnswerControl || (isCall && answerButton != nil),
            hasDeclineControl: hasDeclineControl || (isCall && declineButton != nil),
            replyField: replyField,
            replyButton: replyButton,
            element: element
        )
    }

    private func collectText(from element: AXUIElement, depth: Int) -> [String] {
        let parts = collectTextParts(from: element, depth: depth)
        return parts.icons + parts.others
    }

    private struct StructuredBannerFields {
        var appName: String?
        var title: String?
        var subtitle: String?
        var body: String?
    }

    /// Sequoia/Tahoe banners tag static texts as `title` / `subtitle` / `body`.
    private func collectStructuredBannerFields(from element: AXUIElement) -> StructuredBannerFields {
        var fields = StructuredBannerFields()
        collectStructuredBannerFields(from: element, depth: 0, into: &fields)
        return fields
    }

    private func collectStructuredBannerFields(
        from element: AXUIElement,
        depth: Int,
        into fields: inout StructuredBannerFields
    ) {
        guard depth < 6 else { return }
        let identifier = (AXHelpers.identifier(of: element) ?? "").lowercased()
        let value = AXHelpers.value(of: element)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !value.isEmpty, !NotificationAppCatalog.isInternalAccessibilityLabel(value) {
            switch identifier {
            case "title":
                if fields.title == nil { fields.title = value }
                if NotificationAppCatalog.isExactAppName(value), fields.appName == nil {
                    fields.appName = value
                }
            case "subtitle":
                if fields.subtitle == nil { fields.subtitle = value }
            case "body", "message":
                if fields.body == nil { fields.body = value }
            case "appname", "app", "application":
                if fields.appName == nil { fields.appName = value }
            default:
                break
            }
        }
        for child in AXHelpers.children(of: element) {
            collectStructuredBannerFields(from: child, depth: depth + 1, into: &fields)
        }
    }

    /// Splits `AXAttributedDescription` ("App, Title, Body") into trimmed tokens.
    private static func attributedDescriptionParts(from element: AXUIElement) -> [String] {
        guard let raw = AXHelpers.attributedDescription(of: element)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return []
        }
        return raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !NotificationAppCatalog.isInternalAccessibilityLabel($0) }
    }

    private func collectTextParts(from element: AXUIElement, depth: Int) -> (icons: [String], others: [String]) {
        guard depth < 8 else { return ([], []) }

        var icons: [String] = []
        var others: [String] = []
        let role = AXHelpers.role(of: element) ?? ""

        if role == "AXStaticText" || role == "AXTextArea" || role == "AXTextField" {
            for candidate in [
                AXHelpers.value(of: element),
                AXHelpers.title(of: element),
                AXHelpers.description(of: element),
                AXHelpers.label(of: element),
                AXHelpers.help(of: element),
            ] {
                if let text = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !text.isEmpty,
                   !NotificationAppCatalog.isInternalAccessibilityLabel(text) {
                    others.append(text)
                    break
                }
            }
        } else if role == "AXImage" {
            for candidate in [
                AXHelpers.description(of: element),
                AXHelpers.title(of: element),
                AXHelpers.label(of: element),
                AXHelpers.help(of: element),
            ] {
                guard let raw = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !raw.isEmpty,
                      let label = NotificationAppCatalog.iconIdentityLabel(fromAccessibilityLabel: raw),
                      !icons.contains(label) else {
                    continue
                }
                icons.append(label)
            }
        } else if let title = AXHelpers.title(of: element)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty,
                  role != "AXButton",
                  !NotificationAppCatalog.isInternalAccessibilityLabel(title) {
            others.append(title)
        }

        for child in AXHelpers.children(of: element) {
            let childParts = collectTextParts(from: child, depth: depth + 1)
            icons.append(contentsOf: childParts.icons)
            others.append(contentsOf: childParts.others)
        }

        return (icons, others)
    }

    private func collectButtons(from element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
        guard depth < 14 else { return [] }

        var buttons: [AXUIElement] = []
        let role = AXHelpers.role(of: element) ?? ""
        // Continuity/CallKit czasem eksponuje akcje jako CheckBox / PopUp, nie tylko AXButton.
        if role == "AXButton"
            || role == "AXMenuButton"
            || role == "AXRadioButton"
            || role == "AXCheckBox"
            || role == "AXPopUpButton" {
            buttons.append(element)
        }
        for child in AXHelpers.children(of: element) {
            buttons.append(contentsOf: collectButtons(from: child, depth: depth + 1))
        }
        return buttons
    }

    private func inferBundleID(from texts: [String], buttons: [String]) -> String {
        NotificationAppCatalog.resolve(contentTexts: texts + buttons).delivering
    }

    private func appDisplayName(for bundleID: String) -> String {
        NotificationAppCatalog.name(for: bundleID)
    }

    /// Mocne sygnały call — bundle Phone/FaceTime sam nie wystarczy (inaczej cały Phone.app = false positive).
    private func isCallBanner(
        deliveringBundleID: String,
        serviceBundleID: String,
        axDeliveringBundleID: String?,
        iconLabels: [String],
        texts: [String],
        buttons: [String],
        actionButtonCount: Int,
        hasAnswerControl: Bool,
        hasDeclineControl: Bool
    ) -> Bool {
        if hasAnswerControl && hasDeclineControl {
            return true
        }

        for label in iconLabels {
            let lower = label.lowercased()
            if Self.callAppLabels.contains(where: { lower.contains($0) }) {
                return true
            }
        }

        let title = texts.first ?? ""
        let body = texts.dropFirst().joined(separator: " · ")
        if NotificationAppCatalog.looksLikeCallNotification(title: title, body: body, iconLabels: iconLabels) {
            return true
        }

        let combined = (texts + buttons).joined(separator: " ").lowercased()
        if Self.callKeywords.contains(where: { combined.contains($0) }) {
            return true
        }

        let bundleCandidates = [axDeliveringBundleID, deliveringBundleID, serviceBundleID]
            .compactMap { $0 }
            .map { NotificationAppCatalog.canonicalBundleID(for: $0) }
        let fromCallHost = bundleCandidates.contains(where: { NotificationAppCatalog.callBundleIDs.contains($0) })
            || NotificationAppCatalog.isCallRelatedBundleHint(axDeliveringBundleID)

        // Host Phone/FaceTime + choć jeden przycisk akcji / para przycisków = baner połączenia.
        if fromCallHost, hasAnswerControl || hasDeclineControl || actionButtonCount >= 2 {
            return true
        }

        if hasAnswerControl || hasDeclineControl {
            return fromCallHost
                || Self.callKeywords.contains(where: { combined.contains($0) })
                || actionButtonCount >= 2
        }

        return false
    }

    private static func findButton(in element: AXUIElement, matching keywords: [String], depth: Int = 0) -> AXUIElement? {
        guard depth < 10 else { return nil }

        if AXHelpers.role(of: element) == "AXButton" {
            let title = [
                AXHelpers.title(of: element),
                AXHelpers.description(of: element),
                AXHelpers.label(of: element),
                AXHelpers.value(of: element),
            ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: " ")
            if keywords.contains(where: { title.contains($0) }) {
                return element
            }
        }

        for child in AXHelpers.children(of: element) {
            if let match = findButton(in: child, matching: keywords, depth: depth + 1) {
                return match
            }
        }
        return nil
    }

    private static let callAppLabels = [
        "facetime", "telefon", "phone", "anruf", "chiamata", "llamada", "mobilephone"
    ]

    private func buttonAccessibilityText(_ element: AXUIElement) -> String {
        [
            AXHelpers.title(of: element),
            AXHelpers.description(of: element),
            AXHelpers.value(of: element),
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
        .lowercased()
    }

    private func isAnswerButton(_ element: AXUIElement) -> Bool {
        let title = buttonAccessibilityText(element)
        return Self.answerKeywords.contains { title.contains($0) }
    }

    private func isDeclineButton(_ element: AXUIElement) -> Bool {
        let title = buttonAccessibilityText(element)
        return Self.declineKeywords.contains { title.contains($0) }
    }

    // Localized banner/button keywords for supported system languages (en, pl, de, it, es).
    private static let answerKeywords = [
        "answer", "accept",           // en
        "odbierz",                    // pl
        "annehmen",                   // de
        "rispondi", "accetta",        // it
        "contestar", "responder", "aceptar", // es
    ]

    private static let declineKeywords = [
        "decline", "reject", "end",   // en
        "odrzuć", "odrzuc", "zakończ", // pl
        "ablehnen", "beenden",        // de
        "rifiuta", "termina",         // it
        "rechazar", "finalizar",      // es
    ]

    private static let callKeywords = [
        "incoming call", "incoming", "facetime", "telefon", "calling", "ringing",  // en/shared
        "połączenie", "przychodzące", "dzwoni",                                    // pl
        "eingehender anruf", "anruf",                                              // de
        "chiamata in arrivo", "chiamata",                                          // it
        "llamada entrante", "llamada",                                             // es
    ]

    private static let replyKeywords = [
        "reply", "respond",
        "odpowiedz", "odpowiedź",
        "antworten",
        "rispondi",
        "responder",
    ]

    private static let sendKeywords = [
        "send", "submit",
        "wyślij", "wyslij",
        "senden",
        "invia",
        "enviar",
    ]

    private static func findTextField(in element: AXUIElement, depth: Int = 0) -> AXUIElement? {
        guard depth < 10 else { return nil }
        let role = AXHelpers.role(of: element) ?? ""
        if role == "AXTextField" || role == "AXTextArea" {
            return element
        }
        for child in AXHelpers.children(of: element) {
            if let match = findTextField(in: child, depth: depth + 1) {
                return match
            }
        }
        return nil
    }
}
