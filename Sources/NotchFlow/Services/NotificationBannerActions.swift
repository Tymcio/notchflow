import ApplicationServices
import Foundation

/// Accessibility actions on a live Notification Center banner (close, quick reply).
/// Every call is synchronous IPC to Notification Center, bounded by `AXHelpers.messagingTimeout`.
enum NotificationBannerActions {
    /// Keyword button / text-field searches stop this deep below the banner element.
    static let keywordSearchDepth = 10

    /// Closes the system banner via its "Close" action or a close-like button.
    static func dismiss(_ element: AXUIElement) -> Bool {
        if AXHelpers.performCloseAction(on: element) { return true }
        if let close = findButton(in: element, matching: closeKeywords), AXHelpers.press(close) {
            return true
        }
        return false
    }

    /// Best-effort quick reply via the banner's text field / Reply button.
    static func sendReply(on banner: ParsedNotificationBanner, text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if let field = banner.replyField ?? (banner.element.flatMap { findTextField(in: $0) }) {
            _ = AXHelpers.focused(field)
            if AXHelpers.setValue(trimmed, on: field) {
                if let send = banner.replyButton
                    ?? findButton(in: banner.element ?? field, matching: sendKeywords)
                    ?? findButton(in: banner.element ?? field, matching: replyKeywords) {
                    return AXHelpers.press(send)
                }
                // Some banners submit on Return via the focused field's default action.
                return AXHelpers.press(field)
            }
        }

        if let reply = banner.replyButton
            ?? (banner.element.flatMap { findButton(in: $0, matching: replyKeywords) }) {
            // Reveal the inline field, then try again once.
            guard AXHelpers.press(reply), let element = banner.element else { return false }
            if let field = findTextField(in: element) {
                _ = AXHelpers.focused(field)
                if AXHelpers.setValue(trimmed, on: field) {
                    if let send = findButton(in: element, matching: sendKeywords) {
                        return AXHelpers.press(send)
                    }
                    return AXHelpers.press(field)
                }
            }
            return true
        }

        return false
    }

    /// First `AXButton` (depth-first) whose title / description / label / value contains a keyword.
    static func findButton(in element: AXUIElement, matching keywords: [String], depth: Int = 0) -> AXUIElement? {
        guard depth < keywordSearchDepth else { return nil }

        if AXHelpers.role(of: element) == "AXButton" {
            let text = buttonKeywordText(element)
            if keywords.contains(where: { text.contains($0) }) {
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

    static func findTextField(in element: AXUIElement, depth: Int = 0) -> AXUIElement? {
        guard depth < keywordSearchDepth else { return nil }
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

    static func buttonKeywordText(_ element: AXUIElement) -> String {
        [
            AXHelpers.title(of: element),
            AXHelpers.description(of: element),
            AXHelpers.label(of: element),
            AXHelpers.value(of: element),
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        .joined(separator: " ")
    }

    // Localized button keywords for supported system languages (en, pl, de, it, es).
    static let closeKeywords = [
        "close", "clear", "dismiss",
        "zamknij", "wyczyść", "usuń",
        "schließen", "chiudi", "cerrar",
    ]

    static let replyKeywords = [
        "reply", "respond",
        "odpowiedz", "odpowiedź",
        "antworten",
        "rispondi",
        "responder",
    ]

    static let sendKeywords = [
        "send", "submit",
        "wyślij", "wyslij",
        "senden",
        "invia",
        "enviar",
    ]
}
