import AppKit
import Foundation
import SwiftUI

/// Mapowanie słów kluczowych i bundli — natywne apki + agregatory (Rambox itd.).
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
            if bundleID == "com.apple.MobileSMS" {
                return loc("Messages")
            }
            return name
        }
    }

    static let aggregators: [Entry] = [
        Entry(
            name: "Rambox",
            bundleID: "com.rambox",
            alternateBundleIDs: ["com.saenzramiro.rambox"],
            keywords: ["rambox"],
            brand: BrandBadge(symbol: "tray.full.fill", gradient: [Color(red: 0.93, green: 0.33, blue: 0.24), Color(red: 0.78, green: 0.18, blue: 0.14)])
        ),
        Entry(
            name: "Rambox CE",
            bundleID: "com.grupovrs.ramboxce",
            alternateBundleIDs: [],
            keywords: ["rambox"],
            brand: BrandBadge(symbol: "tray.full.fill", gradient: [Color(red: 0.20, green: 0.55, blue: 0.95), Color(red: 0.10, green: 0.38, blue: 0.82)])
        )
    ]

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
            keywords: ["messages", "imessage", "wiadomości", "nachrichten", "messaggi", "mensajes"],
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
        Entry(
            name: "Skype",
            bundleID: "com.skype.skype",
            alternateBundleIDs: ["com.microsoft.skype"],
            keywords: ["skype"],
            brand: BrandBadge(symbol: "video.fill", gradient: [Color(red: 0.00, green: 0.69, blue: 0.94), Color(red: 0.00, green: 0.52, blue: 0.78)])
        )
    ]

    private static var allEntries: [Entry] {
        aggregators + messagingApps
    }

    static var suggestedApps: [(name: String, bundleID: String)] {
        allEntries.map { ($0.localizedName, $0.bundleID) }
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
        entry(forAnyBundleID: bundleID)?.brand
    }

    static func isAggregator(_ bundleID: String) -> Bool {
        aggregators.contains { matches(bundleID: bundleID, entry: $0) }
    }

    struct Resolution {
        let delivering: String
        let service: String
        let displayName: String
        /// True when `delivering` came from the banner's AX stacking identifier, not text guessing.
        let hasTrustedSource: Bool
    }

    static func resolve(from texts: [String], deliveringHint: String? = nil) -> Resolution {
        let haystack = texts.joined(separator: " ").lowercased()

        var delivering = "unknown.app"
        var isForeignTrustedApp = false
        if let deliveringHint {
            if let entry = entry(forAnyBundleID: deliveringHint) {
                delivering = entry.bundleID
            } else if deliveringHint.lowercased().contains("rambox") {
                delivering = aggregators[0].bundleID
            } else {
                delivering = deliveringHint
                isForeignTrustedApp = true
            }

            // Kontener (Rambox) w AXStackingIdentifier, ale baner jest z innej apki (np. Cursor).
            if isAggregator(delivering),
               let foreign = matchRunningApp(in: texts),
               !isAggregator(foreign) {
                delivering = foreign
                isForeignTrustedApp = true
            }
        } else if let runningApp = matchRunningApp(in: texts) {
            // Baner z tytułem/treścią innej działającej apki (np. Cursor) — nie przypisuj Ramboxowi.
            delivering = runningApp
            isForeignTrustedApp = true
        } else {
            for aggregator in aggregators where aggregator.keywords.contains(where: { haystack.contains($0) }) {
                delivering = aggregator.bundleID
                break
            }

            // Jeśli w tekście nie ma „Rambox”, sprawdź czy aplikacja jest uruchomiona i banner wygląda na webową.
            if delivering == "unknown.app", isRamboxRunning, looksLikeRamboxNotification(texts) {
                delivering = aggregators[0].bundleID
            }
        }

        // AX czasem zwraca Rambox jako nadawcę kontenera, choć baner jest z innej apki.
        if let foreign = matchRunningApp(in: texts),
           !isAggregator(foreign),
           isAggregator(delivering) || delivering == "unknown.app" {
            delivering = foreign
            isForeignTrustedApp = true
        }

        // Serwis (WhatsApp, Messenger…) zgaduj z tekstu tylko dla agregatorów i nieznanych nadawców —
        // baner z Cursora wspominający „telegram” nie jest wiadomością z Telegrama.
        var service = "unknown.app"
        if !isForeignTrustedApp {
            for app in messagingApps where app.keywords.contains(where: { haystack.contains($0) }) {
                service = app.bundleID
                break
            }
        }

        // Natywna apka bez agregatora — delivering = service
        if delivering == "unknown.app", service != "unknown.app" {
            delivering = service
        }

        let displayName: String
        if service != "unknown.app" {
            displayName = name(for: service)
        } else if isForeignTrustedApp {
            displayName = runningAppName(for: delivering) ?? delivering
        } else if delivering != "unknown.app" {
            displayName = name(for: delivering)
        } else {
            displayName = loc("Notification")
        }

        return Resolution(
            delivering: delivering,
            service: service,
            displayName: displayName,
            hasTrustedSource: deliveringHint != nil && isForeignTrustedApp
        )
    }

    private static func runningAppName(for bundleID: String) -> String? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.localizedName
    }

    static func name(for bundleID: String) -> String {
        if let entry = entry(forAnyBundleID: bundleID) {
            return entry.localizedName
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

    private static var isRamboxRunning: Bool {
        aggregators.contains { entry in
            entry.allBundleIDs.contains { bundleID in
                NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty == false
            }
        }
    }

    /// Rambox często wysyła: nadawca + treść bez nazwy serwisu w tekście.
    private static func looksLikeRamboxNotification(_ texts: [String]) -> Bool {
        guard texts.count >= 2 else { return false }
        let joined = texts.joined(separator: " ").lowercased()
        let hasKnownService = messagingApps.contains { app in
            app.keywords.contains { joined.contains($0) }
        }
        guard !hasKnownService else { return false }
        // Baner pasujący do innej działającej apki (np. Cursor) nie jest z Ramboxa.
        return matchRunningApp(in: texts) == nil
    }

    /// Dopasowuje nazwę działającej apki (np. „Cursor”) w dowolnej linii banera.
    static func matchRunningApp(in texts: [String]) -> String? {
        let knownBundleIDs = Set(allEntries.flatMap(\.allBundleIDs))
        let candidates = texts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        guard !candidates.isEmpty else { return nil }
        let haystack = candidates.joined(separator: " ")

        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  let bundleID = app.bundleIdentifier,
                  !knownBundleIDs.contains(bundleID),
                  let name = app.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                  name.count >= 3 else {
                continue
            }
            if candidates.contains(name) {
                return bundleID
            }
            if candidates.contains(where: { line in
                line.hasPrefix(name + " ") || line.hasPrefix(name + "–") || line.hasPrefix(name + "-")
            }) {
                return bundleID
            }
            if haystack.contains(name) {
                return bundleID
            }
        }
        return nil
    }

    /// Baner wygląda na wiadomość z agregatora (nadawca + treść), a nie na powiadomienie innej apki.
    static func looksLikeGenericMessagingBanner(title: String, body: String) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !body.isEmpty else { return false }
        return matchRunningApp(in: [title, body]) == nil
    }
}
