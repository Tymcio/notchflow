import EventKit
import AppKit
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
    var onAccessChange: ((Bool) -> Void)?

    private(set) var upcomingEvent: CalendarEventPreview? {
        didSet { onEventChange?(upcomingEvent) }
    }

    private(set) var dayEvents: [CalendarEventPreview] = [] {
        didSet { onDayEventsChange?(dayEvents) }
    }

    private(set) var hasAccess = false {
        didSet {
            guard oldValue != hasAccess else { return }
            onAccessChange?(hasAccess)
        }
    }

    private let store = EKEventStore()
    private var refreshTask: Task<Void, Never>?

    /// Prompts the user for calendar access (system dialog). Call only from an explicit user action.
    func ensureAccess() async {
        hasAccess = await requestAccess()
        if hasAccess {
            await refreshUpcomingEvent()
            await refreshDayEvents()
        }
    }

    /// Reads the current authorization status without showing the system prompt.
    func refreshAccessStatus() async {
        hasAccess = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        if hasAccess {
            await refreshUpcomingEvent()
            await refreshDayEvents()
        }
    }

    func events(on date: Date) async -> [CalendarEventPreview] {
        guard hasAccess else { return [] }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return []
        }

        let predicate = store.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
        return store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .prefix(8)
            .map { makePreview(from: $0) }
    }

    func openDayInCalendarApp(_ date: Date) {
        NSApp.activate(ignoringOtherApps: true)

        if openCalendarDayWithAppleScript(date) {
            return
        }

        openCalendarApplicationOnly()
    }

    func openEventInCalendarApp(_ event: CalendarEventPreview) {
        if let meetingURL = event.meetingURL {
            NSApp.activate(ignoringOtherApps: true)
            NSWorkspace.shared.open(meetingURL)
            return
        }
        openDayInCalendarApp(event.startDate)
    }

    private func openCalendarDayWithAppleScript(_ date: Date) -> Bool {
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            return false
        }

        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let second = components.second ?? 0

        let scriptSource = """
        set targetDate to (current date)
        set year of targetDate to \(year)
        set month of targetDate to \(month)
        set day of targetDate to \(day)
        set hours of targetDate to \(hour)
        set minutes of targetDate to \(minute)
        set seconds of targetDate to \(second)
        tell application "Calendar"
            activate
            view calendar at targetDate
        end tell
        """

        guard let script = NSAppleScript(source: scriptSource) else { return false }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        return error == nil
    }

    private func openCalendarApplicationOnly() {
        guard let calendarApp = Self.calendarApplicationURL() else { return }
        NSWorkspace.shared.open(calendarApp)
    }

    private static func calendarApplicationURL() -> URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            return url
        }

        for path in ["/System/Applications/Calendar.app", "/Applications/Calendar.app"] {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
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
