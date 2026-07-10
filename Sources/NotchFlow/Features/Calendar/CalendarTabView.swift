import SwiftUI

struct CalendarTabView: View {
    @State private var visibleMonth = Date()

    private var weeks: [CalendarWeek] {
        MonthCalendarModel.weeks(for: visibleMonth)
    }

    var body: some View {
        VStack(spacing: 6) {
            header
            weekdayHeader
            monthGrid
        }
        .foregroundStyle(IslandStyle.primaryText)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                visibleMonth = MonthCalendarModel.previousMonth(from: visibleMonth)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(IslandStyle.secondaryText)

            Text(MonthCalendarModel.monthTitle(for: visibleMonth))
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)

            Button {
                visibleMonth = MonthCalendarModel.nextMonth(from: visibleMonth)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(IslandStyle.secondaryText)
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            Text("T")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(IslandStyle.tertiaryText)
                .frame(width: 22)

            ForEach(MonthCalendarModel.weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(IslandStyle.tertiaryText)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthGrid: some View {
        VStack(spacing: 2) {
            ForEach(weeks) { week in
                HStack(spacing: 0) {
                    Text("\(week.weekNumber)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(IslandStyle.secondaryText)
                        .frame(width: 22)

                    ForEach(week.days) { day in
                        dayCell(day)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: CalendarDay) -> some View {
        let textColor: Color = {
            if day.isToday { return Color.black.opacity(0.85) }
            if day.isCurrentMonth { return IslandStyle.primaryText }
            return IslandStyle.tertiaryText
        }()

        Text("\(day.number)")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(textColor)
            .frame(width: 20, height: 20)
            .background {
                if day.isToday {
                    Circle().fill(Color.white.opacity(0.92))
                }
            }
    }
}
