import AppKit
import Foundation
import SwiftUI

/// Mapowanie oficjalnych aplikacji powiadomień (komunikatory + Apple Mail).
enum NotificationAppCatalog {
    struct BrandBadge: Sendable {
        let symbol: String
        let gradient: [Color]
    }

    struct Entry: Sendable {
        let name: String
        let bundleID: String
        let alternateBundleIDs: [String]
        let keywords: [String]
        let brand: BrandBadge?

        var allBundleIDs: [String] {
            [bundleID] + alternateBundleIDs
        }

        var localizedName: String {
            switch bundleID {
            case "com.apple.MobileSMS":
                return loc("Messages")
            case "com.apple.mail":
                return loc("Mail")
            default:
                return name
            }
        }
    }

    static let messagingApps: [Entry] = [
        Entry(
            name: "WhatsApp",
            bundleID: "net.whatsapp.WhatsApp",
            alternateBundleIDs: ["desktop.WhatsApp"],
            keywords: ["whatsapp"],
            brand: BrandBadge(symbol: "phone.fill", gradient: [Color(red: 0.15, green: 0.83, blue: 0.40), Color(red: 0.08, green: 0.68, blue: 0.32)])
        ),
        Entry(
            name: "Signal",
            bundleID: "org.whispersystems.signal-desktop",
            alternateBundleIDs: [],
            keywords: ["signal"],
            brand: BrandBadge(symbol: "bubble.left.fill", gradient: [Color(red: 0.23, green: 0.46, blue: 0.94), Color(red: 0.14, green: 0.34, blue: 0.82)])
        ),
        Entry(
            name: "Telegram",
            bundleID: "org.telegram.desktop",
            alternateBundleIDs: ["ru.keepcoder.Telegram", "ph.telegra.Telegraph"],
            keywords: ["telegram"],
            brand: BrandBadge(symbol: "paperplane.fill", gradient: [Color(red: 0.16, green: 0.67, blue: 0.93), Color(red: 0.09, green: 0.52, blue: 0.82)])
        ),
        Entry(
            name: "Messages",
            bundleID: "com.apple.MobileSMS",
            alternateBundleIDs: [],
            keywords: ["messages", "imessage", "sms", "text message", "wiadomości", "nachrichten", "messaggi", "mensajes"],
            brand: BrandBadge(symbol: "message.fill", gradient: [Color(red: 0.28, green: 0.86, blue: 0.39), Color(red: 0.12, green: 0.72, blue: 0.30)])
        ),
        Entry(
            name: "Messenger",
            bundleID: "com.facebook.archon",
            alternateBundleIDs: ["com.facebook.Messenger"],
            keywords: ["messenger", "msn", "facebook"],
            brand: BrandBadge(symbol: "bolt.fill", gradient: [Color(red: 0.45, green: 0.32, blue: 0.96), Color(red: 0.00, green: 0.52, blue: 1.00)])
        ),
        Entry(
            name: "Slack",
            bundleID: "com.tinyspeck.slackmacgap",
            alternateBundleIDs: ["com.tinyspeck.slack"],
            keywords: ["slack"],
            brand: BrandBadge(symbol: "number", gradient: [Color(red: 0.58, green: 0.20, blue: 0.58), Color(red: 0.29, green: 0.08, blue: 0.29)])
        ),
        Entry(
            name: "Discord",
            bundleID: "com.hnc.Discord",
            alternateBundleIDs: [],
            keywords: ["discord"],
            brand: BrandBadge(symbol: "gamecontroller.fill", gradient: [Color(red: 0.45, green: 0.52, blue: 0.95), Color(red: 0.34, green: 0.40, blue: 0.82)])
        ),
    ]

    static let emailApps: [Entry] = [
        Entry(
            name: "Mail",
            bundleID: "com.apple.mail",
            alternateBundleIDs: [],
            keywords: ["mail", "email", "e-mail", "poczta"],
            brand: BrandBadge(symbol: "envelope.fill", gradient: [Color(red: 0.20, green: 0.55, blue: 0.95), Color(red: 0.10, green: 0.38, blue: 0.82)])
        ),
    ]

    private static var allEntries: [Entry] {
        messagingApps + emailApps
    }

    static var supportedNotificationApps: [Entry] {
        allEntries
    }

    static var suggestedApps: [(name: String, bundleID: String)] {
        allEntries.map { ($0.localizedName, $0.bundleID) }
    }

    static var installedSupportedApps: [Entry] {
        allEntries.filter { isInstalled($0.bundleID) }
    }

    /// Kept for call sites; Rambox support was removed.
    @available(*, deprecated, message: "Rambox support removed")
    static var installedAggregators: [Entry] { [] }

    static var installedNativeMessagingApps: [Entry] {
        installedSupportedApps
    }

    static func isInstalled(_ bundleID: String) -> Bool {
        bundleIDCandidates(for: bundleID).contains { candidate in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: candidate) != nil
        }
    }

    static var messagingBundleIDs: Set<String> {
        Set(messagingApps.map(\.bundleID))
    }

    static func bundleIDCandidates(for bundleID: String) -> [String] {
        if let entry = entry(forAnyBundleID: bundleID) {
            return entry.allBundleIDs
        }
        return [bundleID]
    }

    static func canonicalBundleID(for bundleID: String) -> String {
        entry(forAnyBundleID: bundleID)?.bundleID ?? bundleID
    }

    static func brandBadge(for bundleID: String) -> BrandBadge? {
        if bundleID == genericNotificationBundleID {
            return genericNotificationBadge
        }
        if bundleID == genericMessagingBundleID {
            return genericMessagingBadge
        }
        return entry(forAnyBundleID: bundleID)?.brand
    }

    /// Fallback icon when the banner cannot be tied to a known app.
    static let genericNotificationBundleID = "unknown.app"
    /// Jedna ikona dla wszystkich powiadomień wiadomościowych w notchu.
    static let genericMessagingBundleID = "messaging.generic"
    /// Marker in release binary — compile_and_run.sh greps this to verify a fresh build.
    static let notificationIconResolverTag = "notchflow-icon-resolver-v8"

    static let genericNotificationBadge = BrandBadge(
        symbol: "bell.fill",
        gradient: [
            Color(red: 1.0, green: 0.62, blue: 0.04),
            Color(red: 0.96, green: 0.40, blue: 0.08),
        ]
    )

    static let genericMessagingBadge = BrandBadge(
        symbol: "message.fill",
        gradient: [
            Color(red: 0.28, green: 0.86, blue: 0.39),
            Color(red: 0.12, green: 0.72, blue: 0.30),
        ]
    )

    /// Only catalog apps may use the real macOS app icon — avoids Raycast etc. as false positives.
    static func isRecognizedNotificationIcon(_ bundleID: String) -> Bool {
        bundleID != genericNotificationBundleID && isCatalogApp(bundleID)
    }

    static func isAggregator(_ bundleID: String) -> Bool {
        false
    }

    static func isMessagingApp(_ bundleID: String) -> Bool {
        messagingApps.contains { matches(bundleID: bundleID, entry: $0) }
    }

    static func isEmailApp(_ bundleID: String) -> Bool {
        emailApps.contains { matches(bundleID: bundleID, entry: $0) }
    }

    static func isSupportedNotificationApp(_ bundleID: String) -> Bool {
        isMessagingApp(bundleID) || isEmailApp(bundleID)
    }

    /// True when a banner text line is exactly a catalog app name (icon label), not a message sender.
    static func isExactAppName(_ text: String) -> Bool {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return false }
        return allEntries.contains { entry in
            entry.name.lowercased() == lower || entry.localizedName.lowercased() == lower
        }
    }

    /// Matches messaging/email app from icon description — exact name only.
    static func matchMessagingAppByExactName(in texts: [String]) -> Entry? {
        for text in texts {
            let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !lower.isEmpty else { continue }
            for app in allEntries {
                if app.name.lowercased() == lower || app.localizedName.lowercased() == lower {
                    return app
                }
            }
        }
        return nil
    }

    /// Keyword match in full banner text — only for banners without a trusted foreign deliverer.
    static func matchMessagingAppByKeyword(in texts: [String]) -> Entry? {
        let haystack = texts.joined(separator: " ").lowercased()
        return allEntries.first { app in
            app.keywords.contains { haystack.contains($0) }
        }
    }

    /// Match on short icon labels (AXImage description) — exact name / bundle ID only.
    static func matchMessagingAppFromIconLabels(in iconTexts: [String]) -> Entry? {
        for text in iconTexts {
            if isNativeMessagesSource(text) {
                return messagingApps.first { $0.bundleID == "com.apple.MobileSMS" }
            }
            if let entry = catalogApp(fromAccessibilityLabel: text) {
                return entry
            }
        }
        return matchMessagingAppByExactName(in: iconTexts)
    }

    /// Catalog app from AX label — including reverse-DNS icon descriptions (e.g. Signal).
    static func catalogApp(fromAccessibilityLabel text: String) -> Entry? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let parsed = bundleID(fromStackingIdentifier: trimmed),
           let entry = entry(forAnyBundleID: parsed),
           isSupportedNotificationApp(entry.bundleID) {
            return entry
        }
        return nil
    }

    /// Stable icon-label token for AXImage — keeps catalog identity even when AX exposes a bundle ID.
    static func iconIdentityLabel(fromAccessibilityLabel text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !isInternalAccessibilityLabel(trimmed) {
            return trimmed
        }
        return catalogApp(fromAccessibilityLabel: trimmed)?.name
    }

    /// Matches messaging app from icon description (e.g. „Signal”) or keyword in banner text.
    static func matchMessagingApp(in texts: [String]) -> Entry? {
        matchMessagingAppByExactName(in: texts) ?? matchMessagingAppByKeyword(in: texts)
    }

    struct Resolution {
        let delivering: String
        let service: String
        let displayName: String
        /// True when `delivering` came from the banner's AX stacking identifier, not text guessing.
        let hasTrustedSource: Bool
    }

    static func resolve(
        iconTexts: [String] = [],
        contentTexts: [String],
        deliveringHint: String? = nil
    ) -> Resolution {
        let messagingFromLabel = matchMessagingAppFromIconLabels(in: iconTexts)

        var delivering = "unknown.app"
        var service = "unknown.app"
        var isForeignTrustedApp = false
        var trustCatalogHint = false

        if let deliveringHint {
            if let entry = entry(forAnyBundleID: deliveringHint) {
                delivering = entry.bundleID
                if isSupportedNotificationApp(entry.bundleID) {
                    service = entry.bundleID
                    trustCatalogHint = true
                }
            } else if isBlockedForeignMatcher(deliveringHint) {
                if let matched = messagingFromLabel {
                    delivering = matched.bundleID
                    service = matched.bundleID
                    trustCatalogHint = true
                }
            } else if isInternalAccessibilityLabel(deliveringHint) {
                if let extracted = bundleID(fromStackingIdentifier: deliveringHint) {
                    delivering = canonicalBundleID(for: extracted)
                    if isSupportedNotificationApp(delivering) {
                        service = delivering
                        trustCatalogHint = true
                    }
                }
            } else {
                delivering = deliveringHint
                isForeignTrustedApp = true
            }
        } else if let runningApp = matchForeignPoster(iconTexts: iconTexts, contentTexts: contentTexts) {
            delivering = runningApp
            isForeignTrustedApp = true
        }

        // Exact icon label for a supported app — never override a trusted foreign poster.
        if let matched = messagingFromLabel, !isForeignTrustedApp {
            delivering = matched.bundleID
            service = matched.bundleID
            trustCatalogHint = true
        }

        if !trustCatalogHint,
           messagingFromLabel == nil,
           let foreign = matchForeignPoster(iconTexts: iconTexts, contentTexts: contentTexts),
           delivering == "unknown.app" {
            delivering = foreign
            isForeignTrustedApp = true
        }

        if service == "unknown.app" {
            if let matched = messagingFromLabel {
                service = matched.bundleID
            } else if isSupportedNotificationApp(delivering) {
                service = delivering
            }
        }

        if delivering == "unknown.app", service != "unknown.app" {
            delivering = service
        } else if delivering != "unknown.app",
                  service == "unknown.app",
                  isSupportedNotificationApp(delivering) {
            service = delivering
        }

        let displayName: String
        if service != "unknown.app" {
            displayName = name(for: service)
        } else if isForeignTrustedApp {
            if isInternalAccessibilityLabel(delivering) {
                displayName = loc("Notification")
            } else {
                displayName = runningAppName(for: delivering) ?? name(for: delivering)
            }
        } else if delivering != "unknown.app" {
            displayName = name(for: delivering)
        } else {
            displayName = loc("Notification")
        }

        return Resolution(
            delivering: delivering,
            service: service,
            displayName: displayName,
            hasTrustedSource: isForeignTrustedApp
                || trustCatalogHint
                || deliveringHint.map { entry(forAnyBundleID: $0) != nil } ?? false
        )
    }

    private static func runningAppName(for bundleID: String) -> String? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.localizedName
    }

    static func name(for bundleID: String) -> String {
        // Catalog first — reverse-DNS bundle IDs also match isInternalAccessibilityLabel.
        if let entry = entry(forAnyBundleID: bundleID) {
            return entry.localizedName
        }
        // Phone/FaceTime aren't messaging-catalog apps; never map their bundle IDs to "Notification".
        if isCallUIHostBundleID(bundleID) || callBundleIDs.contains(bundleID) {
            for candidate in bundleIDCandidates(for: bundleID) {
                if let running = runningAppName(for: candidate) { return running }
            }
            let lower = bundleID.lowercased()
            if lower.contains("facetime") { return "FaceTime" }
            return "Phone"
        }
        if isInternalAccessibilityLabel(bundleID) {
            return loc("Notification")
        }
        return bundleID
    }

    static func keyword(for bundleID: String) -> String? {
        entry(forAnyBundleID: bundleID)?.keywords.first
    }

    private static func entry(forAnyBundleID bundleID: String) -> Entry? {
        allEntries.first { matches(bundleID: bundleID, entry: $0) }
    }

    private static func matches(bundleID: String, entry: Entry) -> Bool {
        entry.allBundleIDs.contains(bundleID)
    }

    /// Accepts only values that look like a bundle identifier (reverse-DNS, no whitespace).
    static func bundleID(fromStackingIdentifier identifier: String?) -> String? {
        guard let raw = identifier?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }

        if raw.lowercased().hasPrefix("widget-local:") {
            return bundleIDFromWidgetLocalIdentifier(raw)
        }

        return normalizedBundleIdentifier(raw)
    }

    /// Tekst nadaje się do pokazania użytkownikowi w notchu (nie surowy AX/widget ID).
    static func isReadableNotificationText(title: String, body: String) -> Bool {
        let titleTrimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let bodyTrimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if titleTrimmed.isEmpty, bodyTrimmed.isEmpty { return false }

        let titleOk = !titleTrimmed.isEmpty
            && !isInternalAccessibilityLabel(titleTrimmed)
            && !isBlockedNotificationContent(title: titleTrimmed, body: "")
        let bodyOk = !bodyTrimmed.isEmpty
            && !isInternalAccessibilityLabel(bodyTrimmed)
            && !isBlockedNotificationContent(title: bodyTrimmed, body: "")

        return titleOk || bodyOk
    }

    private static func normalizedBundleIdentifier(_ candidate: String) -> String? {
        guard !candidate.isEmpty,
              !candidate.contains(":"),
              candidate.contains("."),
              candidate.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            return nil
        }
        return candidate
    }

    private static func bundleIDFromWidgetLocalIdentifier(_ raw: String) -> String? {
        guard raw.lowercased().hasPrefix("widget-local:") else { return nil }
        let remainder = raw.dropFirst("widget-local:".count)
        for part in remainder.split(separator: ":").map(String.init).reversed() {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if let id = normalizedBundleIdentifier(trimmed) {
                return id
            }
        }
        return nil
    }

    static func isNativeMessagesSource(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        if canonicalBundleID(for: bundleID) == "com.apple.MobileSMS" { return true }
        let lower = bundleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Tylko dokładna nazwa / MobileSMS — nie substring „messages” w innych etykietach.
        return lower.contains("mobilesms")
            || lower == "messages"
            || lower == "wiadomości"
            || lower == "nachrichten"
            || lower == "messaggi"
            || lower == "mensajes"
    }

    static func isRamboxSource(_ bundleID: String?) -> Bool {
        false
    }

    /// AX stacking identifier → canonical bundle when available.
    static func axSourceBundleID(from hint: String?) -> String? {
        guard let parsed = bundleID(fromStackingIdentifier: hint) else { return nil }
        return canonicalBundleID(for: parsed)
    }

    /// Aplikacje, które nie powinny przejmować banerów na podstawie treści wiadomości.
    static let blockedForeignMatchers: Set<String> = [
        "com.raycast.macos",
    ]

    static func isBlockedForeignMatcher(_ bundleID: String) -> Bool {
        blockedForeignMatchers.contains(bundleID)
    }

    /// Bezpieczny bundle ID do wyświetlenia w notchu — nigdy Raycast ani inne obce apki.
    static func sanitizedIconBundleID(_ bundleID: String?) -> String {
        guard let bundleID,
              bundleID != genericNotificationBundleID,
              bundleID != notificationIconResolverTag,
              !isBlockedForeignMatcher(bundleID) else {
            return genericNotificationBundleID
        }
        if bundleID == genericMessagingBundleID {
            return genericMessagingBundleID
        }
        // Phone/FaceTime aren't messaging-catalog apps — keep them for real app icons.
        if isCallUIHostBundleID(bundleID) || callBundleIDs.contains(canonicalBundleID(for: bundleID)) {
            return canonicalBundleID(for: bundleID)
        }
        guard isMessagingApp(bundleID) || isEmailApp(bundleID) || isCatalogApp(bundleID) else {
            return genericNotificationBundleID
        }
        return bundleID
    }

    /// Baner wygląda na prywatną wiadomość (SMS/iMessage), a nie na powiadomienie innej apki.
    static func looksLikePersonalMessage(title: String, body: String) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !body.isEmpty else { return false }
        if isBlockedNotificationContent(title: title, body: body) { return false }
        if looksLikeCallNotification(title: title, body: body, iconLabels: []) { return false }
        let haystack = "\(title) \(body)".lowercased()
        let otherApps = messagingApps.filter { $0.bundleID != "com.apple.MobileSMS" }
        guard !otherApps.contains(where: { app in
            app.keywords.contains { haystack.contains($0) }
        }) else { return false }
        return matchRunningApp(in: [title]) == nil
    }

    static let callBundleIDs: Set<String> = [
        "com.apple.FaceTime",
        "com.apple.mobilephone",
        "com.apple.phone",
        "com.apple.TelephonyUtilities",
        "com.apple.CallKitUI",
        "com.apple.IncomingCall",
    ]

    /// Processes whose *presence* means a ringing/active Continuity call UI (not daemons).
    /// `callservicesd` / TelephonyUtilities is always running — never treat it as a ring signal.
    static let callUIHostBundleIDs: Set<String> = [
        "com.apple.FaceTime",
        "com.apple.mobilephone",
        "com.apple.phone",
        "com.apple.CallKitUI",
        "com.apple.IncomingCall",
    ]

    static func isCallUIHostBundleID(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return callUIHostBundleIDs.contains(canonicalBundleID(for: bundleID))
    }

    /// Nagłówki systemowych powiadomień — nie traktuj jak SMS (Status, Następne itd.).
    static func isBlockedNotificationContent(title: String, body: String) -> Bool {
        let titleLower = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let bodyLower = body.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if blockedNotificationHeaders.contains(titleLower) { return true }
        if blockedNotificationHeaders.contains(bodyLower) { return true }
        let combined = "\(titleLower) \(bodyLower)"
        return blockedNotificationPhrases.contains(where: { combined.contains($0) })
    }

    private static let blockedNotificationHeaders: Set<String> = [
        "status", "następne", "next", "upcoming", "notification", "powiadomienie", "notifications",
        "mitteilung", "mitteilungen", "notifica", "notifiche", "notificación", "alert", "alerta",
        "reminder", "przypomnienie", "focus", "skupienie", "battery", "bateria", "wifi", "bluetooth",
        "airdrop", "screen time", "czas przed ekranem", "update", "aktualizacja", "backup", "kopia",
        "calendar", "kalendarz", "event", "wydarzenie", "scheduled", "zaplanowane",
    ]

    private static let blockedNotificationPhrases = [
        "następne:", "next:", "status:", "upcoming:", "scheduled for", "zaplanowano na",
    ]

    /// Heurystyka połączenia — używana gdy AX nie poda bundle ID ani etykiet przycisków.
    static func looksLikeCallNotification(title: String, body: String, iconLabels: [String]) -> Bool {
        let combined = "\(title) \(body) \(iconLabels.joined(separator: " "))".lowercased()
        if callNotificationKeywords.contains(where: { combined.contains($0) }) {
            return true
        }
        for label in iconLabels {
            let lower = label.lowercased()
            if callIconLabels.contains(where: { lower.contains($0) }) {
                return true
            }
        }
        return false
    }

    private static let callNotificationKeywords = [
        "incoming call", "incoming", "facetime", "telefon", "calling", "ringing",
        "połączenie", "przychodzące", "dzwoni", "połączenie przychodzące",
        "eingehender anruf", "anruf", "chiamata in arrivo", "chiamata",
        "llamada entrante", "llamada", "on iphone", "na iphone", "from iphone", "z iphone",
        "apple watch", "zegarek", "facetime_notification",
    ]

    private static let callIconLabels = [
        "facetime", "telefon", "phone", "anruf", "chiamata", "llamada", "mobilephone", "call",
    ]

    static func isCallRelatedBundleHint(_ hint: String?) -> Bool {
        guard let hint else { return false }
        let lower = hint.lowercased()
        return callIconLabels.contains(where: { lower.contains($0) })
            || lower.contains("telephony")
            || lower.contains("callkit")
            || lower.contains("facetime")
            || lower.contains("mobilephone")
            || lower.contains("incomingcall")
    }

    /// Etykiety chrome banera połączenia w NC — nie traktuj jak imię/numer dzwoniącego.
    static func isSystemCallUILabel(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if trimmed == "…" || trimmed == "..." { return true }
        if isInternalAccessibilityLabel(trimmed) { return true }
        if isExactAppName(trimmed) { return false }
        if isBlockedNotificationContent(title: trimmed, body: "") { return true }
        if looksLikeCallNotification(title: trimmed, body: "", iconLabels: []) { return true }
        if isCalendarChromeLabel(trimmed) { return true }

        let lower = trimmed.lowercased()
        let chromeFragments = [
            "centrum powiadomień", "notification center", "powiadomienie", "notification",
            "status", "następne", "approve", "terminal command", "cursor", "agent",
            "control center", "centrum sterowania", "process-only-ring",
            "facetime_notification", "facetime notification",
            "chce uzyskać dostęp", "wants to access", "would like to access",
            "zugriff auf", "deseas acceder", "desidera accedere",
            // Phone.app sidebar/tab labels (OCR of the wrong window must not become the caller)
            "ulubione", "favorites", "ostatnie", "recents", "poczta głosowa",
            "voicemail", "klawiatura", "keypad", "kontakty", "contacts",
        ]
        if chromeFragments.contains(where: { lower == $0 || lower.contains($0) }) {
            return true
        }
        if isContinuityDeviceRouteLabel(trimmed) { return true }
        if lower.contains("widżet") || lower.contains("widget") { return true }
        return false
    }

    /// Phone.app AX often exposes audio routes as "Mikrofon (iPhone (Marcin))" — not the caller.
    static func isContinuityDeviceRouteLabel(_ text: String) -> Bool {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return true }
        let routeTokens = [
            "mikrofon", "microphone", "kamera", "camera",
            "głośnik", "głośniki", "speaker", "speakers",
            "audio", "iphone cellular",
        ]
        let looksLikeRoute = routeTokens.contains { lower.hasPrefix($0) || lower.contains("\($0) (") }
        if looksLikeRoute, lower.contains("iphone") || lower.contains("(") { return true }
        // "Something (iPhone (Name))" device pattern without a person-first token.
        if lower.range(of: #"^.+\(iphone\b"#, options: .regularExpression) != nil,
           routeTokens.contains(where: { lower.contains($0) }) {
            return true
        }
        return false
    }

    /// Dni tygodnia / miesiące / „dziś” z Calendar Up Next — nie mylić z dzwoniącym.
    static func isCalendarChromeLabel(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if isSingleCalendarToken(trimmed) { return true }

        // "NIEDZIELA, 19 LIPCA" — every comma/dot segment is calendar chrome.
        let parts = trimmed
            .components(separatedBy: CharacterSet(charactersIn: ",·|/"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if parts.count >= 2, parts.allSatisfy(isSingleCalendarToken) {
            return true
        }
        return false
    }

    private static func isSingleCalendarToken(_ text: String) -> Bool {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return true }
        let labels: Set<String> = [
            // Weekdays
            "niedziela", "poniedziałek", "wtorek", "środa", "czwartek", "piątek", "sobota",
            "sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday",
            "sonntag", "montag", "dienstag", "mittwoch", "donnerstag", "freitag", "samstag",
            "domenica", "lunedì", "martedì", "mercoledì", "giovedì", "venerdì", "sabato",
            "domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado",
            // Relative / calendar chrome
            "dziś", "dzisiaj", "jutro", "wczoraj", "today", "tomorrow", "yesterday",
            "heute", "morgen", "gestern", "oggi", "domani", "ieri", "hoy", "mañana", "ayer",
            "up next", "następne", "all-day", "cały dzień",
        ]
        if labels.contains(lower) { return true }

        // "19 LIPCA", "19 lipca", "July 19", "19.07"
        let monthDay = #"^\d{1,2}(\s+|\.)(stycznia|lutego|marca|kwietnia|maja|czerwca|lipca|sierpnia|września|października|listopada|grudnia|january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|oct|nov|dec|\d{1,2})$"#
        if lower.range(of: monthDay, options: .regularExpression) != nil { return true }
        return false
    }

    /// Continuity subtitle under the caller name on Phone/FaceTime banners.
    static func isContinuityCallSubtitle(_ text: String) -> Bool {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let marks = [
            "z twojego iphone", "z twojego iphone'a", "from your iphone",
            "von deinem iphone", "dal tuo iphone", "desde tu iphone",
            "iphone cellular", "calls from iphone",
        ]
        return marks.contains { lower.contains($0) }
    }

    /// Imię/numer kontaktu nadający się do UI połączenia (nie chrome NC / nie nazwa apki).
    static func isPlausibleCallerName(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, trimmed.count <= 64 else { return false }
        if isSystemCallUILabel(trimmed) { return false }
        if isExactAppName(trimmed) { return false }
        if isInternalAccessibilityLabel(trimmed) { return false }
        if isCalendarChromeLabel(trimmed) { return false }

        // Phone numbers.
        let digits = trimmed.filter(\.isNumber)
        if digits.count >= 6, digits.count >= trimmed.filter({ $0.isLetter || $0.isNumber }).count - 2 {
            return true
        }

        // Person-like: at least one letter, not a sentence / path / command.
        guard trimmed.contains(where: \.isLetter) else { return false }
        if trimmed.contains("/") || trimmed.contains("://") { return false }
        if trimmed.lowercased().hasPrefix("cd ") { return false }
        if trimmed.contains("•") { return false }
        // TCC / Settings sentences are never caller names.
        if trimmed.count > 40, trimmed.contains(" ") { return false }
        if trimmed.contains("„") || trimmed.contains("\"") { return false }
        return true
    }

    /// Wewnętrzne identyfikatory AX/widgetów (np. widget-local:com.apple.iCloud…).
    static func isInternalAccessibilityLabel(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let lower = trimmed.lowercased()

        if lower.hasPrefix("widget-local:") { return true }
        if lower.hasPrefix("group.") { return true }
        if lower.hasPrefix("stacking-") { return true }
        if trimmed.contains(":"), lower.contains("com.") { return true }

        // Reverse-DNS bez spacji — bundle ID z AX, nie imię kontaktu.
        if !trimmed.contains(" "),
           trimmed.contains("."),
           trimmed.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil,
           trimmed.filter({ $0 == "." }).count >= 2,
           lower.hasPrefix("com.") || lower.hasPrefix("org.") || lower.hasPrefix("net.") {
            return true
        }

        return false
    }

    /// Wybiera pierwszy sensowny wiersz z banera połączenia (pomija Status, Następne, „Połączenie przychodzące” itd.).
    static func bestCallerName(from lines: [String], appName: String) -> String {
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !isSystemCallUILabel(trimmed) else { continue }
            return trimmed
        }
        let app = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !app.isEmpty, !isSystemCallUILabel(app) { return app }
        return app.isEmpty ? "…" : app
    }

    /// Wykrywanie banera połączenia — scoring zamiast surowego „2 przyciski = call”.
    static func isLikelyIncomingCallBanner(
        title: String,
        body: String,
        iconLabels: [String],
        axDeliveringBundleID: String?,
        actionButtonCount: Int,
        hasAnswerControl: Bool,
        hasDeclineControl: Bool,
        isCallFlag: Bool
    ) -> Bool {
        incomingCallScore(
            title: title,
            body: body,
            iconLabels: iconLabels,
            axDeliveringBundleID: axDeliveringBundleID,
            actionButtonCount: actionButtonCount,
            hasAnswerControl: hasAnswerControl,
            hasDeclineControl: hasDeclineControl,
            isCallFlag: isCallFlag
        ) >= 3
    }

    /// Punkty pewności banera połączenia (próg ≥ 3).
    /// `title`/`body` powinny zawierać surowe teksty AX (w tym „Połączenie przychodzące”),
    /// nie tylko wyświetlaną nazwę dzwoniącego — inaczej keyword ginie po filtrze UI.
    static func incomingCallScore(
        title: String,
        body: String,
        iconLabels: [String],
        axDeliveringBundleID: String?,
        actionButtonCount: Int,
        hasAnswerControl: Bool,
        hasDeclineControl: Bool,
        isCallFlag: Bool
    ) -> Int {
        var score = 0

        if isCallFlag { score += 4 }
        if isCallRelatedBundleHint(axDeliveringBundleID) { score += 2 }

        let bundleCandidates = [axDeliveringBundleID]
            .compactMap { $0 }
            .map { canonicalBundleID(for: $0) }
        if bundleCandidates.contains(where: { callBundleIDs.contains($0) }) {
            score += 2
        }

        if hasAnswerControl && hasDeclineControl {
            score += 3
        } else if hasAnswerControl || hasDeclineControl {
            score += 2
        }

        let looksLikeCall = looksLikeCallNotification(title: title, body: body, iconLabels: iconLabels)
        // Sam keyword Continuity („Połączenie przychodzące”) musi wystarczyć — AX często
        // nie eksponuje przycisków Odbierz/Odrzuć jako AXButton.
        if looksLikeCall {
            score += 3
        }

        let messagingIcon = matchMessagingAppFromIconLabels(in: iconLabels)
        let isMessaging = messagingIcon.map { isMessagingApp($0.bundleID) } ?? false

        if actionButtonCount >= 2, !isMessaging {
            score += 2
        }

        if isLikelyFalseCallChrome(
            title: title,
            body: body,
            iconLabels: iconLabels,
            actionButtonCount: actionButtonCount,
            axDeliveringBundleID: axDeliveringBundleID
        ) {
            score -= 3
        }

        let onlyInternalText =
            (isInternalAccessibilityLabel(title) || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && (isInternalAccessibilityLabel(body) || body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || body == title)
        if onlyInternalText,
           !looksLikeCall,
           !hasAnswerControl,
           !hasDeclineControl,
           !isCallRelatedBundleHint(axDeliveringBundleID) {
            score -= 5
        }

        if isMessaging, actionButtonCount < 2, !hasAnswerControl, !hasDeclineControl, !looksLikeCall {
            score -= 4
        }

        return score
    }

    /// NC czasem pokazuje „Następne” + generyczne „Połączenie przychodzące” bez prawdziwego połączenia.
    static func isLikelyFalseCallChrome(
        title: String,
        body: String,
        iconLabels: [String],
        actionButtonCount: Int,
        axDeliveringBundleID: String?
    ) -> Bool {
        if isCallRelatedBundleHint(axDeliveringBundleID) { return false }

        let bundleCandidates = iconLabels.compactMap { bundleID(fromStackingIdentifier: $0) }
        if bundleCandidates.contains(where: { callBundleIDs.contains(canonicalBundleID(for: $0)) }) {
            return false
        }

        guard isBlockedNotificationContent(title: title, body: "") else { return false }

        let caller = bestCallerName(from: [title, body], appName: "")
        if caller != "…", !isInternalAccessibilityLabel(caller), !isSystemCallUILabel(caller) {
            return false
        }
        if isExactAppName(caller) { return false }

        let bodyTrimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return bodyTrimmed.isEmpty || isSystemCallUILabel(bodyTrimmed)
    }

    /// Dopasowuje obcą apkę tylko po etykiecie ikony lub krótkim nagłówku — nie po treści SMS.
    private static func matchForeignPoster(iconTexts: [String], contentTexts: [String]) -> String? {
        if let fromIcon = matchRunningApp(in: iconTexts) {
            return fromIcon
        }
        guard let header = contentTexts.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              !header.isEmpty,
              header.count <= 32 else {
            return nil
        }
        return matchRunningApp(in: [header])
    }

    /// Dopasowuje nazwę działającej apki tylko po pełnej linii (dokładne dopasowanie),
    /// nigdy po fragmencie w treści wiadomości (np. „Raycast” w SMS ≠ aplikacja Raycast).
    static func matchRunningApp(in texts: [String]) -> String? {
        let knownBundleIDs = Set(allEntries.flatMap(\.allBundleIDs))
        let candidates = texts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        guard !candidates.isEmpty else { return nil }

        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  let bundleID = app.bundleIdentifier,
                  !knownBundleIDs.contains(bundleID),
                  !blockedForeignMatchers.contains(bundleID),
                  let name = app.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                  name.count >= 3 else {
                continue
            }
            for candidate in candidates where candidate == name {
                return bundleID
            }
        }
        return nil
    }

    static func isCatalogApp(_ bundleID: String) -> Bool {
        entry(forAnyBundleID: bundleID) != nil
    }

    /// Baner wygląda na wiadomość z agregatora (nadawca + treść), a nie na powiadomienie innej apki.
    static func looksLikeGenericMessagingBanner(title: String, body: String) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !body.isEmpty else { return false }
        if isBlockedNotificationContent(title: title, body: body) { return false }
        if looksLikeCallNotification(title: title, body: body, iconLabels: []) { return false }
        return matchRunningApp(in: [title, body]) == nil
    }
}
