import ApplicationServices
import CoreGraphics
import Foundation

/// A Notification Center banner read through Accessibility.
///
/// `@unchecked Sendable`: the only non-Sendable members are `AXUIElement` references, which
/// are immutable CF handles to another process' UI and may be used from any thread.
struct ParsedNotificationBanner: @unchecked Sendable {
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
    /// Scored at parse time from raw AX text — call banners are dropped, never shown.
    let isCall: Bool
    /// True gdy nadawcę potwierdza AX stacking identifier — nie tylko heurystyka tekstowa.
    let hasTrustedSource: Bool
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

/// Static texts Sequoia/Tahoe tag with `title` / `subtitle` / `body` identifiers.
struct NotificationBannerStructuredFields: Equatable, Sendable {
    var appName: String?
    var title: String?
    var subtitle: String?
    var body: String?
}

/// A button-like control found inside a banner candidate.
struct NotificationBannerButton: Equatable, Sendable {
    let role: String
    /// Lowercased title / description / value.
    let accessibilityText: String
    /// Lowercased title / description / label / value (keyword search).
    let keywordText: String
    /// Depth below the banner candidate element.
    let depth: Int

    init(role: String, accessibilityText: String, keywordText: String, depth: Int) {
        self.role = role
        self.accessibilityText = accessibilityText
        self.keywordText = keywordText
        self.depth = depth
    }
}

/// Everything the parser needs from one AX element, read in a single subtree walk.
/// Plain data (plus opaque element handles) so parsing is testable without Accessibility.
struct NotificationBannerSnapshot: @unchecked Sendable {
    var frame: CGRect
    var role: String
    var isNotificationCenterBanner: Bool
    var deliveringBundleHint: String?
    /// Identity labels from `AXImage` descendants.
    var iconTexts: [String] = []
    /// Static text / titles from descendants, in tree order.
    var otherTexts: [String] = []
    var structured = NotificationBannerStructuredFields()
    var attributedDescription: String?
    var buttons: [NotificationBannerButton] = []
    var element: AXUIElement?
    var replyField: AXUIElement?
    var replyButton: AXUIElement?
}

/// Pure banner classification: AX snapshot → `ParsedNotificationBanner`.
enum NotificationBannerParser {
    /// Smallest frame any banner candidate can have (call-shaped / NC-subrole banners).
    static let minimumCandidateSize = CGSize(width: 60, height: 24)
    /// Phone.app / FaceTime incoming UI can be taller than a NC toast.
    static let maximumCandidateHeight: CGFloat = 720

    static let allowedRoles: Set<String> = [
        "AXWindow", "AXGroup", "AXScrollArea", "AXSheet", "AXPopover", "AXToolbar",
        "AXLayoutArea", "AXList", "AXRow", "AXCell", "AXStaticText",
    ]

    static let buttonRoles: Set<String> = [
        "AXButton", "AXMenuButton", "AXRadioButton", "AXCheckBox", "AXPopUpButton",
    ]

    /// Cheap pre-filter on the frame alone — lets the scanner skip the subtree walk.
    static func frameCanBeBanner(_ frame: CGRect) -> Bool {
        frame.width >= minimumCandidateSize.width
            && frame.height >= minimumCandidateSize.height
            && frame.height <= maximumCandidateHeight
    }

    static func parse(_ snapshot: NotificationBannerSnapshot) -> ParsedNotificationBanner? {
        let frame = snapshot.frame
        let buttons = snapshot.buttons
        let buttonCount = buttons.count
        let hint = snapshot.deliveringBundleHint
        let hostIsCallApp = NotificationAppCatalog.callBundleIDs.contains(
            NotificationAppCatalog.canonicalBundleID(for: hint ?? "")
        ) || NotificationAppCatalog.isCallRelatedBundleHint(hint)
        let callShape = buttonCount >= 2
        let isNCBanner = snapshot.isNotificationCenterBanner

        let minWidth: CGFloat = (callShape || isNCBanner) ? 60 : 180
        let minHeight: CGFloat = (callShape || isNCBanner) ? 24 : 36
        guard frame.width >= minWidth, frame.height >= minHeight else { return nil }

        let role = snapshot.role
        if !callShape && !isNCBanner {
            guard allowedRoles.contains(role) else { return nil }
        } else if role == "AXApplication" || role == "AXSystemWide" {
            return nil
        }

        let structured = snapshot.structured
        let attributedParts = attributedDescriptionParts(snapshot.attributedDescription)
        var iconLabels = snapshot.iconTexts + snapshot.otherTexts.filter { NotificationAppCatalog.isExactAppName($0) }
        // App name often lives only in AXAttributedDescription ("Signal, Alice, …").
        if let appToken = attributedParts.first, NotificationAppCatalog.isExactAppName(appToken),
           !iconLabels.contains(where: { $0.caseInsensitiveCompare(appToken) == .orderedSame }) {
            iconLabels.append(appToken)
        }
        if let appName = structured.appName, NotificationAppCatalog.isExactAppName(appName),
           !iconLabels.contains(where: { $0.caseInsensitiveCompare(appName) == .orderedSame }) {
            iconLabels.append(appName)
        }

        var contentCandidates = snapshot.otherTexts
        for field in [structured.title, structured.subtitle, structured.body].compactMap({ $0 })
            where !contentCandidates.contains(field) {
            contentCandidates.append(field)
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

        let buttonTitles = buttons.map(\.accessibilityText).filter { !$0.isEmpty }

        let resolved = NotificationAppCatalog.resolve(
            iconTexts: iconLabels,
            contentTexts: contentCandidates,
            deliveringHint: hint
        )
        let contentTexts = contentCandidates.filter { text in
            if text.lowercased() == "notification center" { return false }
            if NotificationAppCatalog.isExactAppName(text) { return false }
            if NotificationAppCatalog.isInternalAccessibilityLabel(text) { return false }
            return true
        }
        // Raw text for call scoring — keep "Incoming call" style labels here, otherwise the
        // keyword disappears and a call banner slips through as a message.
        let scoreTitle = structured.title ?? contentTexts.first ?? resolved.displayName
        let scoreBody = structured.body
            ?? structured.subtitle
            ?? contentTexts.dropFirst().joined(separator: " · ")

        let senderLines = contentTexts.filter { !NotificationAppCatalog.isSystemCallUILabel($0) }
        var title = structured.title
            ?? NotificationAppCatalog.bestCallerName(
                from: senderLines.isEmpty ? contentTexts : senderLines,
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

        // Sender often sits in the attributed description ("Ada Nowak, mobile").
        if let attr = snapshot.attributedDescription,
           let sender = senderFromCallLikeText(attr) {
            title = sender
        } else if let sender = senderFromCallLikeText(attributedParts.joined(separator: ", ")) {
            title = sender
        } else if let sender = contentTexts.compactMap(plausibleSender).first {
            title = sender
        }

        let hasAnswerControl = buttons.contains { matches($0.accessibilityText, answerKeywords) }
            || buttons.contains { isKeywordButton($0, answerKeywords) }
        let hasDeclineControl = buttons.contains { matches($0.accessibilityText, declineKeywords) }
            || buttons.contains { isKeywordButton($0, declineKeywords) }

        let strongEvidence = hasStrongCallEvidence(
            deliveringBundleID: resolved.delivering,
            serviceBundleID: resolved.service,
            axDeliveringBundleID: hint,
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
            axDeliveringBundleID: hint,
            actionButtonCount: buttonCount,
            hasAnswerControl: hasAnswerControl,
            hasDeclineControl: hasDeclineControl,
            isCallFlag: strongEvidence
        )
        let isCall = callScore >= 3

        let maxHeight: CGFloat = (isCall || hostIsCallApp) ? maximumCandidateHeight : 280
        guard frame.height <= maxHeight else { return nil }

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

        return ParsedNotificationBanner(
            deliveringBundleID: resolved.delivering,
            serviceBundleID: resolved.service,
            axDeliveringBundleID: hint,
            iconLabels: iconLabels,
            appName: resolved.displayName,
            title: displayTitle,
            body: displayBody,
            isCall: isCall,
            hasTrustedSource: resolved.hasTrustedSource,
            actionButtonCount: buttonCount,
            hasAnswerControl: hasAnswerControl,
            hasDeclineControl: hasDeclineControl,
            replyField: isCall ? nil : snapshot.replyField,
            replyButton: isCall ? nil : snapshot.replyButton,
            element: snapshot.element
        )
    }

    /// Splits `AXAttributedDescription` ("App, Title, Body") into trimmed tokens.
    static func attributedDescriptionParts(_ raw: String?) -> [String] {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return []
        }
        return raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !NotificationAppCatalog.isInternalAccessibilityLabel($0) }
    }

    /// "Anna Kowalska, Połączenie przychodzące" / "Ada, mobile" → "Anna Kowalska".
    static func senderFromCallLikeText(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if NotificationAppCatalog.isContinuityDeviceRouteLabel(trimmed) { return nil }
        let lower = trimmed.lowercased()
        // Bare "iphone" matches Continuity mic/camera routes — require stronger call marks.
        guard callTextMarks.contains(where: { lower.contains($0) }) else { return nil }

        let separators = CharacterSet(charactersIn: ",·\n—–-")
        let parts = trimmed.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.lazy.compactMap(plausibleSender).first
    }

    static func plausibleSender(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard NotificationAppCatalog.isPlausibleCallerName(trimmed) else { return nil }
        let lower = trimmed.lowercased()
        if lower == "facetime_notification" || lower.hasPrefix("facetime_") { return nil }
        return trimmed
    }

    /// Strong call signals — a Phone/FaceTime bundle alone is not enough.
    static func hasStrongCallEvidence(
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
            if callAppLabels.contains(where: { lower.contains($0) }) {
                return true
            }
        }

        let title = texts.first ?? ""
        let body = texts.dropFirst().joined(separator: " · ")
        if NotificationAppCatalog.looksLikeCallNotification(title: title, body: body, iconLabels: iconLabels) {
            return true
        }

        let combined = (texts + buttons).joined(separator: " ").lowercased()
        let mentionsCall = callKeywords.contains(where: { combined.contains($0) })
        if mentionsCall {
            return true
        }

        let bundleCandidates = [axDeliveringBundleID, deliveringBundleID, serviceBundleID]
            .compactMap { $0 }
            .map { NotificationAppCatalog.canonicalBundleID(for: $0) }
        let fromCallHost = bundleCandidates.contains(where: { NotificationAppCatalog.callBundleIDs.contains($0) })
            || NotificationAppCatalog.isCallRelatedBundleHint(axDeliveringBundleID)

        if fromCallHost, hasAnswerControl || hasDeclineControl || actionButtonCount >= 2 {
            return true
        }

        if hasAnswerControl || hasDeclineControl {
            return fromCallHost || actionButtonCount >= 2
        }

        return false
    }

    private static func matches(_ text: String, _ keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }

    /// Mirrors a depth-limited search for an `AXButton` whose text contains a keyword.
    private static func isKeywordButton(_ button: NotificationBannerButton, _ keywords: [String]) -> Bool {
        button.role == "AXButton" && button.depth < NotificationBannerActions.keywordSearchDepth
            && matches(button.keywordText, keywords)
    }

    // Localized call keywords for supported system languages (en, pl, de, it, es).
    static let answerKeywords = [
        "answer", "accept",                  // en
        "odbierz",                           // pl
        "annehmen",                          // de
        "rispondi", "accetta",               // it
        "contestar", "responder", "aceptar", // es
    ]

    static let declineKeywords = [
        "decline", "reject", "end",    // en
        "odrzuć", "odrzuc", "zakończ", // pl
        "ablehnen", "beenden",         // de
        "rifiuta", "termina",          // it
        "rechazar", "finalizar",       // es
    ]

    static let callKeywords = [
        "incoming call", "incoming", "facetime", "telefon", "calling", "ringing", // en/shared
        "połączenie", "przychodzące", "dzwoni",                                   // pl
        "eingehender anruf", "anruf",                                             // de
        "chiamata in arrivo", "chiamata",                                         // it
        "llamada entrante", "llamada",                                            // es
    ]

    private static let callTextMarks = [
        "połączenie", "przychodzące", "incoming", "facetime", "mobile",
        "calling", "ringing", "telefon", "anruf", "chiamata", "llamada",
        "facetime_notification", "from your iphone", "z twojego iphone",
        "von deinem iphone", "dal tuo iphone", "desde tu iphone",
    ]

    private static let callAppLabels = [
        "facetime", "telefon", "phone", "anruf", "chiamata", "llamada", "mobilephone",
    ]
}
