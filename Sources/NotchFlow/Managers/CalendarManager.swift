import AppKit
import EventKit
import Foundation

struct CalendarEventPreview: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let meetingURL: URL?

    init(id: String, title: String, startDate: Date, endDate: Date? = nil, meetingURL: URL?) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate ?? startDate
        self.meetingURL = meetingURL
    }

    var timeUntilStart: TimeInterval {
        startDate.timeIntervalSinceNow
    }

    /// "in 25 min" / "za 1 godz. 5 min" in the app's language.
    func formattedCountdown(at date: Date = Date()) -> String {
        locFormat(
            "in %@",
            CalendarEventFormatting.duration(
                startDate.timeIntervalSince(date),
                locale: CalendarEventFormatting.appLocale
            )
        )
    }

    /// Start time in the user's regional time format (12/24 h).
    var formattedStartTime: String {
        startDate.formatted(date: .omitted, time: .shortened)
    }
}

enum CalendarEventFormatting {
    /// Locale for the app's UI language, keeping the user's region for number formats.
    static var appLocale: Locale {
        let language = LanguageResolver.languageCode
        if let region = Locale.current.region?.identifier {
            return Locale(identifier: "\(language)_\(region)")
        }
        return Locale(identifier: language)
    }

    /// Whole minutes / hours until a date ("25 min", "1 hr, 5 min"), never negative.
    static func duration(_ interval: TimeInterval, locale: Locale) -> String {
        let minutes = max(0, Int(interval) / 60)
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let formatter = DateComponentsFormatter()
        formatter.calendar = calendar
        formatter.unitsStyle = .short
        if minutes < 60 {
            formatter.allowedUnits = [.minute]
            formatter.zeroFormattingBehavior = .default
        } else {
            formatter.allowedUnits = [.hour, .minute]
            formatter.zeroFormattingBehavior = .dropAll
        }
        return formatter.string(from: TimeInterval(minutes * 60)) ?? "\(minutes) min"
    }
}

/// Next-event and today's-events feed for the island.
///
/// EventKit is queried on a background queue, and only when something can have changed:
/// `EKEventStoreChanged`, a day change, wake from sleep, or a one-shot timer at the next
/// time an event starts or ends.
@MainActor
final class CalendarManager {
    var onEventChange: ((CalendarEventPreview?) -> Void)?
    var onDayEventsChange: (([CalendarEventPreview]) -> Void)?
    var onAccessChange: ((Bool) -> Void)?

    private(set) var upcomingEvent: CalendarEventPreview? {
        didSet {
            guard oldValue != upcomingEvent else { return }
            onEventChange?(upcomingEvent)
        }
    }

    private(set) var dayEvents: [CalendarEventPreview] = [] {
        didSet {
            guard oldValue != dayEvents else { return }
            onDayEventsChange?(dayEvents)
        }
    }

    private(set) var hasAccess = false {
        didSet {
            guard oldValue != hasAccess else { return }
            onAccessChange?(hasAccess)
        }
    }

    /// Upcoming-event lookahead.
    nonisolated static let upcomingWindow: TimeInterval = 8 * 3600
    /// Re-check at least this often when nothing is scheduled (events entering the lookahead).
    nonisolated static let maximumRefreshInterval: TimeInterval = 3600

    private let store = EKEventStore()
    private let fetchQueue = DispatchQueue(label: "eu.notchflow.calendar-fetch", qos: .utility)
    private var boundaryTimer: Timer?
    private var pendingRefresh: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    /// `@unchecked Sendable`: the store is only used for fetches on `fetchQueue`.
    private struct StoreBox: @unchecked Sendable {
        let store: EKEventStore
    }

    private struct Snapshot: Sendable {
        let upcoming: CalendarEventPreview?
        let day: [CalendarEventPreview]
        let nextBoundary: Date
    }

    /// Prompts the user for calendar access (system dialog). Call only from an explicit user action.
    func ensureAccess() async {
        hasAccess = await requestAccess()
        if hasAccess {
            await refresh()
        }
    }

    /// Reads the current authorization status without showing the system prompt.
    func refreshAccessStatus() async {
        hasAccess = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        if hasAccess {
            await refresh()
        }
    }

    func events(on date: Date) async -> [CalendarEventPreview] {
        guard hasAccess else { return [] }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return []
        }
        let box = StoreBox(store: store)
        return await withCheckedContinuation { continuation in
            fetchQueue.async {
                let events = Self.previews(in: box.store, from: startOfDay, to: endOfDay)
                continuation.resume(returning: Array(events.prefix(8)))
            }
        }
    }

    func openDayInCalendarApp(_ date: Date) {
        NSApp.activate(ignoringOtherApps: true)
        Task {
            if await openCalendarDayWithAppleScript(date) { return }
            Self.openCalendarApplicationOnly()
        }
    }

    func openEventInCalendarApp(_ event: CalendarEventPreview) {
        if let meetingURL = event.meetingURL {
            NSApp.activate(ignoringOtherApps: true)
            NSWorkspace.shared.open(meetingURL)
            return
        }
        openDayInCalendarApp(event.startDate)
    }

    /// Starts change-driven refreshing (idempotent) and refreshes now.
    func startAutoRefresh() {
        if observers.isEmpty {
            let refreshSoon: @Sendable (Notification) -> Void = { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.scheduleRefresh()
                }
            }
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main, using: refreshSoon))
            observers.append(center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main, using: refreshSoon))
            observers.append(center.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main, using: refreshSoon))
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: refreshSoon
            ))
        }
        scheduleRefresh(delay: .zero)
    }

    // MARK: - Refreshing

    /// Coalesces bursts of store-changed notifications into one fetch.
    private func scheduleRefresh(delay: Duration = .milliseconds(500)) {
        pendingRefresh?.cancel()
        pendingRefresh = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    private func refresh() async {
        guard hasAccess else {
            upcomingEvent = nil
            dayEvents = []
            boundaryTimer?.invalidate()
            boundaryTimer = nil
            return
        }

        let now = Date()
        let box = StoreBox(store: store)
        let snapshot: Snapshot = await withCheckedContinuation { continuation in
            fetchQueue.async {
                continuation.resume(returning: Self.snapshot(in: box.store, now: now))
            }
        }
        upcomingEvent = snapshot.upcoming
        dayEvents = snapshot.day
        scheduleBoundaryRefresh(at: snapshot.nextBoundary)
    }

    private func scheduleBoundaryRefresh(at date: Date) {
        boundaryTimer?.invalidate()
        let timer = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleRefresh(delay: .zero)
            }
        }
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        boundaryTimer = timer
    }

    private nonisolated static func snapshot(in store: EKEventStore, now: Date) -> Snapshot {
        let calendar = Calendar.current
        let startOfTomorrow = calendar.date(
            byAdding: .day, value: 1, to: calendar.startOfDay(for: now)
        ) ?? now.addingTimeInterval(24 * 3600)
        let upcomingEnd = now.addingTimeInterval(upcomingWindow)

        let upcomingEvents = previews(in: store, from: now, to: upcomingEnd)
        let dayEvents = previews(in: store, from: now, to: startOfTomorrow)

        return Snapshot(
            upcoming: upcomingEvents.first,
            day: Array(dayEvents.prefix(5)),
            nextBoundary: nextRefreshDate(
                after: now,
                events: upcomingEvents + dayEvents,
                startOfTomorrow: startOfTomorrow
            )
        )
    }

    /// When the lists can next change on their own: an event starts or ends, the day
    /// rolls over, or (at the latest) an hour passes so new events enter the lookahead.
    nonisolated static func nextRefreshDate(
        after now: Date,
        events: [CalendarEventPreview],
        startOfTomorrow: Date
    ) -> Date {
        var next = min(startOfTomorrow, now.addingTimeInterval(maximumRefreshInterval))
        for event in events {
            for boundary in [event.startDate, event.endDate] where boundary > now && boundary < next {
                next = boundary
            }
        }
        return next.addingTimeInterval(1)
    }

    private nonisolated static func previews(in store: EKEventStore, from start: Date, to end: Date) -> [CalendarEventPreview] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .map(makePreview)
    }

    private func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToEvents()
        } catch {
            NotchFlowLog.calendar.error("Calendar access request failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Opening Calendar

    private func openCalendarDayWithAppleScript(_ date: Date) async -> Bool {
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            return false
        }

        let scriptSource = """
        set targetDate to (current date)
        set year of targetDate to \(year)
        set month of targetDate to \(month)
        set day of targetDate to \(day)
        set hours of targetDate to \(components.hour ?? 0)
        set minutes of targetDate to \(components.minute ?? 0)
        set seconds of targetDate to \(components.second ?? 0)
        with timeout of 10 seconds
            tell application "Calendar"
                activate
                view calendar at targetDate
            end tell
        end timeout
        """
        if case .success = await AppleScriptExecutor.shared.run(scriptSource, transform: { _ in true }) {
            return true
        }
        return false
    }

    private static func openCalendarApplicationOnly() {
        guard let calendarApp = calendarApplicationURL() else { return }
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

    private nonisolated static func makePreview(from event: EKEvent) -> CalendarEventPreview {
        CalendarEventPreview(
            id: event.eventIdentifier,
            title: event.title,
            startDate: event.startDate,
            endDate: event.endDate,
            meetingURL: event.url ?? extractMeetingURL(from: event.notes)
        )
    }

    private nonisolated static func extractMeetingURL(from notes: String?) -> URL? {
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
