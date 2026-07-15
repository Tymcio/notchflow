import AppKit
import ApplicationServices
import Foundation
import os

struct ParsedNotificationBanner {
    /// Aplikacja, która wysłała banner macOS (np. Rambox).
    let deliveringBundleID: String
    /// Wywnioskowany serwis wiadomości (np. WhatsApp), jeśli znany.
    let serviceBundleID: String
    let appName: String
    let title: String
    let body: String
    let isCall: Bool
    /// True gdy nadawcę potwierdza AX stacking identifier — nie tylko heurystyka tekstowa.
    let hasTrustedSource: Bool
    let answerButton: AXUIElement?
    let declineButton: AXUIElement?
    /// Element banera — pozwala zamknąć systemowy dymek po pokazaniu w notchu.
    let element: AXUIElement?

    var appBundleID: String { deliveringBundleID }

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
    private var seenFingerprints: [String: Date] = [:]
    private var consecutiveEmptyScans = 0
    private var axObserver: AXObserver?
    private var axObservedPID: pid_t?
    private var eventScanTask: Task<Void, Never>?

    private var pollInterval: Duration {
        // Przy aktywnych banerach szybki cykl (m.in. reconcile stanu połączeń).
        guard consecutiveEmptyScans >= 6 else { return .milliseconds(1_000) }
        // Cisza + działający AXObserver: polling to tylko fallback, może być rzadki.
        return axObserver != nil ? .seconds(15) : .milliseconds(3_000)
    }

    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            consecutiveEmptyScans = 0
            startPolling()
        } else {
            pollTask?.cancel()
            pollTask = nil
            eventScanTask?.cancel()
            eventScanTask = nil
            removeAXObserver()
            consecutiveEmptyScans = 0
        }
    }

    func requestPermission() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func pressAnswer(on banner: ParsedNotificationBanner) {
        guard let button = banner.answerButton else { return }
        _ = AXHelpers.press(button)
    }

    func pressDecline(on banner: ParsedNotificationBanner) {
        guard let button = banner.declineButton else { return }
        _ = AXHelpers.press(button)
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
    private func installAXObserverIfNeeded(pid: pid_t) {
        if axObservedPID == pid, axObserver != nil { return }
        removeAXObserver()

        var observer: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let instance = Unmanaged<NotificationCenterObserver>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor in
                instance.handleAXEvent()
            }
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else {
            Self.logger.debug("AXObserverCreate failed for pid \(pid)")
            return
        }

        let appElement = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        // Destroy-event przyspiesza reconcile (np. koniec połączenia), nie tylko pojawianie się banerów.
        let notifications = [kAXWindowCreatedNotification, kAXCreatedNotification, kAXUIElementDestroyedNotification]
        var registeredAny = false
        for notification in notifications {
            if AXObserverAddNotification(observer, appElement, notification as CFString, refcon) == .success {
                registeredAny = true
            }
        }
        guard registeredAny else {
            Self.logger.debug("AXObserverAddNotification failed for pid \(pid)")
            return
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        axObserver = observer
        axObservedPID = pid
    }

    private func removeAXObserver() {
        if let axObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(axObserver), .defaultMode)
        }
        axObserver = nil
        axObservedPID = nil
    }

    private func handleAXEvent() {
        guard isEnabled else { return }
        eventScanTask?.cancel()
        eventScanTask = Task { @MainActor in
            defer { eventScanTask = nil }
            // Poczekaj aż baner ma pełną treść (ikona apki, tytuł) — wcześniejszy skan mylił Cursor z Ramboxem.
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            await scanForBanners()
        }
    }

    private func scanForBanners() async {
        guard isEnabled, isAccessibilityTrusted else { return }
        guard let pid = AXHelpers.notificationCenterPID() else { return }

        installAXObserverIfNeeded(pid: pid)

        guard notificationCenterMayHaveBanners(pid: pid) else {
            consecutiveEmptyScans += 1
            onScanComplete?([])
            return
        }

        let appElement = AXUIElementCreateApplication(pid)
        let banners = collectBanners(from: appElement, depth: 0)

        if banners.isEmpty {
            consecutiveEmptyScans += 1
        } else {
            consecutiveEmptyScans = 0
        }

        let now = Date()
        seenFingerprints = seenFingerprints.filter { now.timeIntervalSince($0.value) < 30 }

        for banner in banners {
            guard !seenFingerprints.keys.contains(banner.fingerprint) else { continue }
            seenFingerprints[banner.fingerprint] = now
            onBannerDetected?(banner)
        }

        onScanComplete?(banners)
    }

    private func notificationCenterMayHaveBanners(pid: pid_t) -> Bool {
        let appElement = AXUIElementCreateApplication(pid)
        for child in AXHelpers.children(of: appElement) {
            if AXHelpers.isHidden(child) { continue }
            guard let frame = AXHelpers.frame(of: child) else { continue }
            if frame.width >= 180, frame.height >= 36, frame.height <= 240 {
                return true
            }
        }
        return false
    }

    private func collectBanners(
        from element: AXUIElement,
        depth: Int,
        inheritedBundleHint: String? = nil
    ) -> [ParsedNotificationBanner] {
        guard depth < 14 else { return [] }

        // The stacking identifier lives on the banner window; children inherit it so nested
        // groups parse with the same delivering app (keeps fingerprints deduplicated).
        let bundleHint = deliveringBundleHint(for: element, inherited: inheritedBundleHint)

        var results: [ParsedNotificationBanner] = []
        if let parsed = parseBanner(element, deliveringBundleHint: bundleHint) {
            results.append(parsed)
        }

        for child in AXHelpers.children(of: element) {
            if AXHelpers.isHidden(child) { continue }
            results.append(
                contentsOf: collectBanners(from: child, depth: depth + 1, inheritedBundleHint: bundleHint)
            )
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

    /// Accepts only values that look like a bundle identifier (reverse-DNS, no whitespace).
    static func bundleID(fromStackingIdentifier identifier: String?) -> String? {
        guard let identifier = identifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !identifier.isEmpty,
              identifier.contains("."),
              identifier.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            return nil
        }
        return identifier
    }

    private func parseBanner(_ element: AXUIElement, deliveringBundleHint: String?) -> ParsedNotificationBanner? {
        guard let frame = AXHelpers.frame(of: element) else { return nil }
        guard frame.width >= 180, frame.height >= 36, frame.height <= 240 else { return nil }

        let role = AXHelpers.role(of: element) ?? ""
        let allowedRoles = ["AXWindow", "AXGroup", "AXScrollArea", "AXSheet", "AXPopover"]
        guard allowedRoles.contains(role) else { return nil }

        let texts = collectText(from: element, depth: 0)
        guard !texts.isEmpty else { return nil }

        let buttons = collectButtons(from: element)
        let buttonTitles = buttons.compactMap { AXHelpers.title(of: $0) ?? AXHelpers.description(of: $0) }

        let resolved = NotificationAppCatalog.resolve(from: texts, deliveringHint: deliveringBundleHint)
        let contentTexts = texts.filter { text in
            let lower = text.lowercased()
            if lower.contains("rambox") || lower == "notification center" { return false }
            // Etykieta ikony apki (np. „Signal”) — nie traktuj jako nadawcy wiadomości.
            if NotificationAppCatalog.isExactAppName(text) { return false }
            return true
        }
        let title = contentTexts.first ?? resolved.displayName
        let body = contentTexts.dropFirst().joined(separator: " · ")

        let isCall = isCallBanner(
            deliveringBundleID: resolved.delivering,
            serviceBundleID: resolved.service,
            texts: texts,
            buttons: buttonTitles
        )
        let answerButton = buttons.first { isAnswerButton($0) }
        let declineButton = buttons.first { isDeclineButton($0) }

        let isKnownMessaging = NotificationAppCatalog.isMessagingApp(resolved.delivering)
            || NotificationAppCatalog.isMessagingApp(resolved.service)
        guard isCall || !body.isEmpty || contentTexts.count >= 2
            || (isKnownMessaging && !title.isEmpty) else { return nil }

        return ParsedNotificationBanner(
            deliveringBundleID: resolved.delivering,
            serviceBundleID: resolved.service,
            appName: resolved.displayName,
            title: title,
            body: body.isEmpty ? title : body,
            isCall: isCall,
            hasTrustedSource: resolved.hasTrustedSource,
            answerButton: answerButton,
            declineButton: declineButton,
            element: element
        )
    }

    private func collectText(from element: AXUIElement, depth: Int) -> [String] {
        let parts = collectTextParts(from: element, depth: depth)
        return parts.icons + parts.others
    }

    private func collectTextParts(from element: AXUIElement, depth: Int) -> (icons: [String], others: [String]) {
        guard depth < 8 else { return ([], []) }

        var icons: [String] = []
        var others: [String] = []
        let role = AXHelpers.role(of: element) ?? ""

        if role == "AXStaticText" || role == "AXTextArea" || role == "AXTextField" {
            if let value = AXHelpers.value(of: element)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                others.append(value)
            } else if let title = AXHelpers.title(of: element)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                others.append(title)
            }
        } else if role == "AXImage" {
            if let description = AXHelpers.description(of: element)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !description.isEmpty {
                icons.append(description)
            }
        } else if let title = AXHelpers.title(of: element)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty,
                  role != "AXButton" {
            others.append(title)
        }

        for child in AXHelpers.children(of: element) {
            let childParts = collectTextParts(from: child, depth: depth + 1)
            icons.append(contentsOf: childParts.icons)
            others.append(contentsOf: childParts.others)
        }

        return (icons, others)
    }

    private func collectButtons(from element: AXUIElement) -> [AXUIElement] {
        var buttons: [AXUIElement] = []
        if AXHelpers.role(of: element) == "AXButton" {
            buttons.append(element)
        }
        for child in AXHelpers.children(of: element) {
            buttons.append(contentsOf: collectButtons(from: child))
        }
        return buttons
    }

    private func inferBundleID(from texts: [String], buttons: [String]) -> String {
        NotificationAppCatalog.resolve(from: texts + buttons).delivering
    }

    private func appDisplayName(for bundleID: String) -> String {
        NotificationAppCatalog.name(for: bundleID)
    }

    private func isCallBanner(
        deliveringBundleID: String,
        serviceBundleID: String,
        texts: [String],
        buttons: [String]
    ) -> Bool {
        let hasAnswer = buttons.contains { title in
            let lower = title.lowercased()
            return Self.answerKeywords.contains { lower.contains($0) }
        }
        let hasDecline = buttons.contains { title in
            let lower = title.lowercased()
            return Self.declineKeywords.contains { lower.contains($0) }
        }
        guard hasAnswer, hasDecline else { return false }

        if NotificationHubManager.callBundleIDs.contains(deliveringBundleID)
            || NotificationHubManager.callBundleIDs.contains(serviceBundleID) {
            return true
        }

        let combined = (texts + buttons).joined(separator: " ").lowercased()
        return Self.callKeywords.contains { combined.contains($0) }
    }

    private func isAnswerButton(_ element: AXUIElement) -> Bool {
        let title = (AXHelpers.title(of: element) ?? AXHelpers.description(of: element) ?? "").lowercased()
        return Self.answerKeywords.contains { title.contains($0) }
    }

    private func isDeclineButton(_ element: AXUIElement) -> Bool {
        let title = (AXHelpers.title(of: element) ?? AXHelpers.description(of: element) ?? "").lowercased()
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
        "decline", "reject",          // en
        "odrzuć",                     // pl
        "ablehnen",                   // de
        "rifiuta",                    // it
        "rechazar",                   // es
    ]

    private static let callKeywords = [
        "incoming call", "incoming", "facetime", "telefon",  // en/shared
        "połączenie", "przychodzące",                        // pl
        "eingehender anruf", "anruf",                        // de
        "chiamata in arrivo", "chiamata",                    // it
        "llamada entrante", "llamada",                       // es
    ]
}
