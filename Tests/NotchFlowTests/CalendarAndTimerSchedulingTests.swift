import XCTest
@testable import NotchFlow

final class CalendarSchedulingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(startIn start: TimeInterval, endIn end: TimeInterval) -> CalendarEventPreview {
        CalendarEventPreview(
            id: UUID().uuidString,
            title: "Event",
            startDate: now.addingTimeInterval(start),
            endDate: now.addingTimeInterval(end),
            meetingURL: nil
        )
    }

    func testNextRefreshIsTheNearestEventBoundary() {
        let tomorrow = now.addingTimeInterval(10 * 3600)
        let ongoing = event(startIn: -600, endIn: 1200)
        let later = event(startIn: 1800, endIn: 3600)
        let next = CalendarManager.nextRefreshDate(after: now, events: [later, ongoing], startOfTomorrow: tomorrow)
        XCTAssertEqual(next, now.addingTimeInterval(1201), "Ongoing event ends first")
    }

    func testNextRefreshFallsBackToDayChangeOrHourlyCap() {
        let soonMidnight = now.addingTimeInterval(1800)
        XCTAssertEqual(
            CalendarManager.nextRefreshDate(after: now, events: [], startOfTomorrow: soonMidnight),
            soonMidnight.addingTimeInterval(1)
        )
        XCTAssertEqual(
            CalendarManager.nextRefreshDate(after: now, events: [], startOfTomorrow: now.addingTimeInterval(20 * 3600)),
            now.addingTimeInterval(CalendarManager.maximumRefreshInterval + 1)
        )
    }

    func testPastBoundariesAreIgnored() {
        let tomorrow = now.addingTimeInterval(5 * 3600)
        let finished = event(startIn: -7200, endIn: -3600)
        XCTAssertEqual(
            CalendarManager.nextRefreshDate(after: now, events: [finished], startOfTomorrow: tomorrow),
            now.addingTimeInterval(CalendarManager.maximumRefreshInterval + 1)
        )
    }

    func testCountdownDurationIsLocalized() {
        let english = Locale(identifier: "en_US")
        XCTAssertEqual(CalendarEventFormatting.duration(25 * 60 + 30, locale: english), "25 min")
        XCTAssertEqual(CalendarEventFormatting.duration(-90, locale: english), "0 min")
        let englishHours = CalendarEventFormatting.duration(65 * 60, locale: english)
        XCTAssertTrue(englishHours.hasPrefix("1 hr"), englishHours)
        XCTAssertTrue(englishHours.contains("5 min"), englishHours)

        let polish = CalendarEventFormatting.duration(65 * 60, locale: Locale(identifier: "pl_PL"))
        XCTAssertTrue(polish.contains("godz"), polish)
        XCTAssertFalse(polish.contains("hr"), polish)
    }
}

final class FocusTimerTickTests: XCTestCase {
    func testTickAnchorSharesTheSubSecondGridOfThePhaseEnd() {
        let end = Date(timeIntervalSince1970: 1_000.37)
        let activity = FocusTimerActivity(
            formattedTime: "05:00",
            progress: 0,
            isRunning: true,
            modeLabel: "Timer",
            phaseEndDate: end,
            totalSeconds: 300,
            mode: .countdown
        )
        let anchor = IdleTimerView.tickAnchor(for: activity)
        XCTAssertLessThan(anchor, end)
        let offset = end.timeIntervalSince(anchor)
        XCTAssertEqual(offset, offset.rounded(), accuracy: 0.0001)
    }

    func testStopwatchAnchorsOnItsStart() {
        let start = Date(timeIntervalSince1970: 500.5)
        let activity = FocusTimerActivity(
            formattedTime: "00:00",
            progress: 0,
            isRunning: true,
            modeLabel: "Stopwatch",
            stopwatchStartDate: start,
            mode: .stopwatch
        )
        XCTAssertEqual(IdleTimerView.tickAnchor(for: activity), start)
    }

    func testRunningCountdownDerivesTimeFromPhaseEnd() {
        var state = FocusTimerState()
        state.mode = .countdown
        state.isRunning = true
        state.totalSeconds = 300
        state.remainingSeconds = 300
        let end = Date(timeIntervalSince1970: 2_000)
        state.phaseEndDate = end
        XCTAssertEqual(state.formattedTime(at: end.addingTimeInterval(-61)), "01:01")
        XCTAssertEqual(state.remainingSeconds(at: end.addingTimeInterval(5)), 0)
    }
}
