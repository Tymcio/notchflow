import AppKit
import Foundation

/// Mapowanie słów kluczowych i bundli — natywne apki + agregatory (Rambox itd.).
enum NotificationAppCatalog {
    struct Entry: Sendable {
        let name: String
        let bundleID: String
        let keywords: [String]
    }

    static let aggregators: [Entry] = [
        Entry(name: "Rambox", bundleID: "com.saenzramiro.rambox", keywords: ["rambox"]),
        Entry(name: "Rambox CE", bundleID: "com.grupovrs.ramboxce", keywords: ["rambox"])
    ]

    static let messagingApps: [Entry] = [
        Entry(name: "WhatsApp", bundleID: "net.whatsapp.WhatsApp", keywords: ["whatsapp"]),
        Entry(name: "Signal", bundleID: "org.whispersystems.signal-desktop", keywords: ["signal"]),
        Entry(name: "Telegram", bundleID: "ru.keepcoder.Telegram", keywords: ["telegram"]),
        Entry(name: "Wiadomości", bundleID: "com.apple.MobileSMS", keywords: ["messages", "wiadomości", "imessage"]),
        Entry(name: "Messenger", bundleID: "com.facebook.archon", keywords: ["messenger", "msn", "facebook"]),
        Entry(name: "Slack", bundleID: "com.tinyspeck.slackmacgap", keywords: ["slack"]),
        Entry(name: "Discord", bundleID: "com.hnc.Discord", keywords: ["discord"]),
        Entry(name: "Skype", bundleID: "com.skype.skype", keywords: ["skype"])
    ]

    static var suggestedApps: [(name: String, bundleID: String)] {
        aggregators.map { ($0.name, $0.bundleID) }
            + messagingApps.map { ($0.name, $0.bundleID) }
    }

    static func isAggregator(_ bundleID: String) -> Bool {
        aggregators.contains { $0.bundleID == bundleID }
    }

    static var messagingBundleIDs: Set<String> {
        Set(messagingApps.map(\.bundleID))
    }

    static func resolve(from texts: [String]) -> (delivering: String, service: String, displayName: String) {
        let haystack = texts.joined(separator: " ").lowercased()

        var delivering = "unknown.app"
        for aggregator in aggregators where aggregator.keywords.contains(where: { haystack.contains($0) }) {
            delivering = aggregator.bundleID
            break
        }

        // Jeśli w tekście nie ma „Rambox”, sprawdź czy aplikacja jest uruchomiona i banner wygląda na webową.
        if delivering == "unknown.app", isRamboxRunning, looksLikeRamboxNotification(texts) {
            delivering = "com.saenzramiro.rambox"
        }

        var service = "unknown.app"
        for app in messagingApps where app.keywords.contains(where: { haystack.contains($0) }) {
            service = app.bundleID
            break
        }

        // Natywna apka bez agregatora — delivering = service
        if delivering == "unknown.app", service != "unknown.app" {
            delivering = service
        }

        let displayName: String
        if delivering != "unknown.app", service != "unknown.app", delivering != service {
            displayName = name(for: service)
        } else if service != "unknown.app" {
            displayName = name(for: service)
        } else if delivering != "unknown.app" {
            displayName = name(for: delivering)
        } else {
            displayName = "Powiadomienie"
        }

        return (delivering, service, displayName)
    }

    static func name(for bundleID: String) -> String {
        if let entry = (aggregators + messagingApps).first(where: { $0.bundleID == bundleID }) {
            return entry.name
        }
        return bundleID
    }

    static func keyword(for bundleID: String) -> String? {
        (aggregators + messagingApps).first { $0.bundleID == bundleID }?.keywords.first
    }

    private static var isRamboxRunning: Bool {
        aggregators.contains { entry in
            NSRunningApplication.runningApplications(withBundleIdentifier: entry.bundleID).isEmpty == false
        }
    }

    /// Rambox często wysyła: nadawca + treść bez nazwy serwisu w tekście.
    private static func looksLikeRamboxNotification(_ texts: [String]) -> Bool {
        guard texts.count >= 2 else { return false }
        let joined = texts.joined(separator: " ").lowercased()
        let hasKnownService = messagingApps.contains { app in
            app.keywords.contains { joined.contains($0) }
        }
        return !hasKnownService
    }
}
