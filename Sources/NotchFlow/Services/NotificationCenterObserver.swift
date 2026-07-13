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
    let answerButton: AXUIElement?
    let declineButton: AXUIElement?

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

    private var pollInterval: Duration {
        consecutiveEmptyScans >= 6 ? .milliseconds(3_000) : .milliseconds(1_000)
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

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                await scanForBanners()
                try? await Task.sleep(for: pollInterval)
            }
        }
    }

    private func scanForBanners() async {
        guard isEnabled, isAccessibilityTrusted else { return }
        guard let pid = AXHelpers.notificationCenterPID() else { return }

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

    private func collectBanners(from element: AXUIElement, depth: Int) -> [ParsedNotificationBanner] {
        guard depth < 14 else { return [] }

        var results: [ParsedNotificationBanner] = []
        if let parsed = parseBanner(element) {
            results.append(parsed)
        }

        for child in AXHelpers.children(of: element) {
            if AXHelpers.isHidden(child) { continue }
            results.append(contentsOf: collectBanners(from: child, depth: depth + 1))
        }

        return results
    }

    private func parseBanner(_ element: AXUIElement) -> ParsedNotificationBanner? {
        guard let frame = AXHelpers.frame(of: element) else { return nil }
        guard frame.width >= 180, frame.height >= 36, frame.height <= 240 else { return nil }

        let role = AXHelpers.role(of: element) ?? ""
        let allowedRoles = ["AXWindow", "AXGroup", "AXScrollArea", "AXSheet", "AXPopover"]
        guard allowedRoles.contains(role) else { return nil }

        let texts = collectText(from: element, depth: 0)
        guard !texts.isEmpty else { return nil }

        let buttons = collectButtons(from: element)
        let buttonTitles = buttons.compactMap { AXHelpers.title(of: $0) ?? AXHelpers.description(of: $0) }

        let resolved = NotificationAppCatalog.resolve(from: texts)
        let contentTexts = texts.filter { text in
            let lower = text.lowercased()
            return !lower.contains("rambox") && lower != "notification center"
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

        guard isCall || !body.isEmpty || contentTexts.count >= 2 else { return nil }

        return ParsedNotificationBanner(
            deliveringBundleID: resolved.delivering,
            serviceBundleID: resolved.service,
            appName: resolved.displayName,
            title: title,
            body: body.isEmpty ? title : body,
            isCall: isCall,
            answerButton: answerButton,
            declineButton: declineButton
        )
    }

    private func collectText(from element: AXUIElement, depth: Int) -> [String] {
        guard depth < 8 else { return [] }

        var texts: [String] = []
        let role = AXHelpers.role(of: element) ?? ""

        if role == "AXStaticText" || role == "AXTextArea" || role == "AXTextField" {
            if let value = AXHelpers.value(of: element)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                texts.append(value)
            } else if let title = AXHelpers.title(of: element)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                texts.append(title)
            }
        }

        for child in AXHelpers.children(of: element) {
            texts.append(contentsOf: collectText(from: child, depth: depth + 1))
        }

        return texts
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
            return lower.contains("answer") || lower.contains("odbierz") || lower.contains("accept")
        }
        let hasDecline = buttons.contains { title in
            let lower = title.lowercased()
            return lower.contains("decline") || lower.contains("odrzuć") || lower.contains("reject")
        }
        guard hasAnswer, hasDecline else { return false }

        if NotificationHubManager.callBundleIDs.contains(deliveringBundleID)
            || NotificationHubManager.callBundleIDs.contains(serviceBundleID) {
            return true
        }

        let combined = (texts + buttons).joined(separator: " ").lowercased()
        let callKeywords = ["połączenie", "incoming call", "facetime", "telefon", "incoming", "przychodzące"]
        return callKeywords.contains { combined.contains($0) }
    }

    private func isAnswerButton(_ element: AXUIElement) -> Bool {
        let title = (AXHelpers.title(of: element) ?? AXHelpers.description(of: element) ?? "").lowercased()
        return title.contains("answer") || title.contains("odbierz") || title.contains("accept")
    }

    private func isDeclineButton(_ element: AXUIElement) -> Bool {
        let title = (AXHelpers.title(of: element) ?? AXHelpers.description(of: element) ?? "").lowercased()
        return title.contains("decline") || title.contains("odrzuć") || title.contains("reject")
    }
}
