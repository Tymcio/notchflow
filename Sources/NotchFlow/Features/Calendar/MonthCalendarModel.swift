import Foundation

struct CalendarDay: Identifiable, Equatable {
    let date: Date
    let number: Int
    let isCurrentMonth: Bool
    let isToday: Bool

    var id: Date { date }
}

struct CalendarWeek: Identifiable, Equatable {
    let weekNumber: Int
    let days: [CalendarDay]

    var id: Int { weekNumber }
}

enum MonthCalendarModel {
    static var polishCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "pl_PL")
        calendar.firstWeekday = 2
        return calendar
    }

    static let weekdaySymbols = ["Pn", "Wt", "Śr", "Cz", "Pt", "So", "Nd"]

    static func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "LLLL yyyy"
        let title = formatter.string(from: date)
        return title.prefix(1).uppercased() + title.dropFirst()
    }

    static func weeks(for month: Date) -> [CalendarWeek] {
        let calendar = polishCalendar
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: month)),
              let dayRange = calendar.range(of: .day, in: .month, for: month) else {
            return []
        }

        let weekday = calendar.component(.weekday, from: monthStart)
        let leading = (weekday + 5) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -leading, to: monthStart) else {
            return []
        }

        let totalCells = ((leading + dayRange.count + 6) / 7) * 7
        var days: [CalendarDay] = []
        var cursor = gridStart

        for _ in 0..<totalCells {
            days.append(
                CalendarDay(
                    date: cursor,
                    number: calendar.component(.day, from: cursor),
                    isCurrentMonth: calendar.isDate(cursor, equalTo: monthStart, toGranularity: .month),
                    isToday: calendar.isDateInToday(cursor)
                )
            )
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return stride(from: 0, to: days.count, by: 7).map { start in
            let chunk = Array(days[start..<min(start + 7, days.count)])
            let weekNumber = calendar.component(.weekOfYear, from: chunk[0].date)
            return CalendarWeek(weekNumber: weekNumber, days: chunk)
        }
    }

    static func previousMonth(from month: Date) -> Date {
        polishCalendar.date(byAdding: .month, value: -1, to: month) ?? month
    }

    static func nextMonth(from month: Date) -> Date {
        polishCalendar.date(byAdding: .month, value: 1, to: month) ?? month
    }
}

enum CalendarLayoutMetrics {
    private static let sectionSpacing: CGFloat = 8
    private static let headerHeight: CGFloat = 32
    private static let weekdayHeight: CGFloat = 20
    private static let weekRowHeight: CGFloat = 30
    private static let weekRowSpacing: CGFloat = 2
    private static let dayTitleHeight: CGFloat = 20
    private static let eventRowHeight: CGFloat = 52
    private static let eventRowSpacing: CGFloat = 6
    private static let sectionPadding: CGFloat = 10
    private static let safetyMargin: CGFloat = 32

    static func contentHeight(weekCount: Int, eventCount: Int, showsAccessPrompt: Bool) -> CGFloat {
        let upcoming: CGFloat
        if showsAccessPrompt {
            upcoming = 58
        } else if eventCount == 0 {
            upcoming = 40
        } else {
            let visibleEvents = min(eventCount, 8)
            let rows = CGFloat(visibleEvents) * eventRowHeight
            let gaps = CGFloat(max(0, visibleEvents - 1)) * eventRowSpacing
            upcoming = dayTitleHeight + rows + gaps + sectionPadding
        }

        let weeks = CGFloat(max(weekCount, 5))
        let grid = weeks * weekRowHeight + max(0, weeks - 1) * weekRowSpacing
        let stackSpacing = sectionSpacing * 3
        return upcoming + stackSpacing + headerHeight + weekdayHeight + grid + safetyMargin
    }
}
