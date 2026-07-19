import AppKit
import ApplicationServices
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
        NotificationAppCatalog.isLikelyIncomingCallBanner(
            title: title,
            body: body,
            iconLabels: iconLabels,
            axDeliveringBundleID: axDeliveringBundleID,
            actionButtonCount: actionButtonCount,
            hasAnswerControl: hasAnswerControl,
            hasDeclineControl: hasDeclineControl,
            isCallFlag: isCall
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
    private var seenFingerprints: [String: Date] = [:]
    private var consecutiveEmptyScans = 0
    private var axObservers: [pid_t: AXObserver] = [:]
    private var eventScanTask: Task<Void, Never>?
    private var coalesceScanTask: Task<Void, Never>?
    private var scanInFlight = false
    private var scanPending = false

    private static let axMaxDepth = 10
    private static let axMaxNodesPerPID = 1_000

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

    func pressAnswer(on banner: ParsedNotificationBanner) {
        if let button = banner.answerButton, AXHelpers.press(button) {
            return
        }
        if let element = banner.element,
           let button = Self.findButton(in: element, matching: Self.answerKeywords) {
            _ = AXHelpers.press(button)
        }
    }

    func pressDecline(on banner: ParsedNotificationBanner) {
        if let button = banner.declineButton, AXHelpers.press(button) {
            return
        }
        if let element = banner.element,
           let button = Self.findButton(in: element, matching: Self.declineKeywords) {
            _ = AXHelpers.press(button)
        }
    }

    /// Zamyka systemowy dymek (akcja „Close” przez AX) — powiadomienie zostało już pokazane w notchu.
    /// Ponawia próby, bo w trakcie animacji wjazdu akcja „Close” bywa jeszcze niedostępna.
    func dismissBanner(_ banner: ParsedNotificationBanner) {
        guard let element = banner.element else { return }
        Task { @MainActor in
            for attempt in 0..<8 {
                if AXHelpers.performCloseAction(on: element) {
                    return
                }
                try? await Task.sleep(for: .milliseconds(attempt == 0 ? 120 : 180))
            }
            Self.logger.debug("dismissBanner: close action not found for \(banner.title, privacy: .private)")
        }
    }

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

            let appElement = AXUIElementCreateApplication(pid)
            var nodeBudget = Self.axMaxNodesPerPID
            for banner in collectBanners(
                from: appElement,
                depth: 0,
                nodeBudget: &nodeBudget
            ) {
                let key = banner.fingerprint
                guard seenKeys.insert(key).inserted else { continue }
                banners.append(banner)
                if banner.isLikelyCall {
                    foundConfidentCall = true
                }
            }
            if foundConfidentCall, callsPriorityScanning { break }
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
            if callsPriorityScanning, results.contains(where: \.isLikelyCall) {
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

        if callsPriorityScanning, callScore > 0 || buttonCount >= 2 || strongEvidence {
            Self.logger.info(
                """
                call-score=\(callScore, privacy: .public) isCall=\(isCall, privacy: .public) \
                buttons=\(buttonCount, privacy: .public) answer=\(hasAnswerControl, privacy: .public) \
                decline=\(hasDeclineControl, privacy: .public) \
                hint=\(deliveringBundleHint ?? "nil", privacy: .public) \
                title=\(scoreTitle, privacy: .private) body=\(scoreBody, privacy: .private)
                """
            )
        }

        let maxHeight: CGFloat = isCall ? 400 : 280
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

    /// Mocne sygnały call (bundle / keywords / etykiety przycisków) — bez „2 bez ethkiet = call”.
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

        if NotificationAppCatalog.isCallRelatedBundleHint(axDeliveringBundleID) {
            return true
        }

        let bundleCandidates = [axDeliveringBundleID, deliveringBundleID, serviceBundleID]
            .compactMap { $0 }
            .map { NotificationAppCatalog.canonicalBundleID(for: $0) }

        if bundleCandidates.contains(where: { NotificationAppCatalog.callBundleIDs.contains($0) }) {
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

        if hasAnswerControl || hasDeclineControl {
            return bundleCandidates.contains(where: { NotificationAppCatalog.callBundleIDs.contains($0) })
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
