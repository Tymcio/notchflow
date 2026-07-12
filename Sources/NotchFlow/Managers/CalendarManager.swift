import EventKit
import Foundation

struct CalendarEventPreview: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let meetingURL: URL?

    var timeUntilStart: TimeInterval {
        startDate.timeIntervalSinceNow
    }

    var formattedCountdown: String {
        let interval = max(timeUntilStart, 0)
        let minutes = Int(interval) / 60
        if minutes < 60 {
            return "za \(minutes) min"
        }
        let hours = minutes / 60
        return "za \(hours) h \(minutes % 60) min"
    }

    var formattedStartTime: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: startDate)
    }
}

@MainActor
final class CalendarManager {
    var onEventChange: ((CalendarEventPreview?) -> Void)?
    var onDayEventsChange: (([CalendarEventPreview]) -> Void)?

    private(set) var upcomingEvent: CalendarEventPreview? {
        didSet { onEventChange?(upcomingEvent) }
    }

    private(set) var dayEvents: [CalendarEventPreview] = [] {
        didSet { onDayEventsChange?(dayEvents) }
    }

    private(set) var hasAccess = false

    private let store = EKEventStore()
    private var refreshTask: Task<Void, Never>?

    func ensureAccess() async {
        hasAccess = await requestAccess()
    }

    func refreshUpcomingEvent() async {
        guard hasAccess else {
            upcomingEvent = nil
            return
        }

        let now = Date()
        let end = Calendar.current.date(byAdding: .hour, value: 8, to: now) ?? now.addingTimeInterval(8 * 3600)
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        let events = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }

        upcomingEvent = events.first.map { makePreview(from: $0) }
    }

    func refreshDayEvents() async {
        guard hasAccess else {
            dayEvents = []
            return
        }

        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? now
        let predicate = store.predicateForEvents(withStart: now, end: endOfDay, calendars: nil)
        let events = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .prefix(5)

        dayEvents = events.map { makePreview(from: $0) }
    }

    func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                if hasAccess {
                    await refreshUpcomingEvent()
                    await refreshDayEvents()
                }
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToEvents()
        } catch {
            return false
        }
    }

    private func makePreview(from event: EKEvent) -> CalendarEventPreview {
        CalendarEventPreview(
            id: event.eventIdentifier,
            title: event.title,
            startDate: event.startDate,
            meetingURL: event.url ?? extractMeetingURL(from: event.notes)
        )
    }

    private func extractMeetingURL(from notes: String?) -> URL? {
        guard let notes else { return nil }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(notes.startIndex..<notes.endIndex, in: notes)
        let matches = detector?.matches(in: notes, options: [], range: range) ?? []
        return matches.compactMap { $0.url }.first { url in
            let host = url.host?.lowercased() ?? ""
            return host.contains("zoom") || host.contains("meet.google") || host.contains("teams.microsoft")
        } ?? matches.first?.url
    }
}
