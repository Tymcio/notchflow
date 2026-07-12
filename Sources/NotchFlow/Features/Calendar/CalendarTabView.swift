import AppKit
import SwiftUI

struct CalendarTabView: View {
    @Bindable var appState: AppState
    @State private var visibleMonth = Date()

    private var weeks: [CalendarWeek] {
        MonthCalendarModel.weeks(for: visibleMonth)
    }

    var body: some View {
        VStack(spacing: 8) {
            upcomingSection
            header
            weekdayHeader
            monthGrid
        }
        .foregroundStyle(IslandStyle.primaryText)
    }

    @ViewBuilder
    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nadchodzące")
                .font(.caption.weight(.semibold))
                .foregroundStyle(IslandStyle.secondaryText)

            if !appState.calendarManager.hasAccess {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(IslandStyle.tertiaryText)
                    Text("Brak dostępu do kalendarza.")
                        .font(.caption2)
                        .foregroundStyle(IslandStyle.tertiaryText)
                    Spacer(minLength: 0)
                    Button("Udziel dostępu") {
                        Task {
                            await appState.calendarManager.ensureAccess()
                            if appState.calendarManager.hasAccess {
                                appState.calendarManager.startAutoRefresh()
                            }
                        }
                    }
                    .font(.caption2.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(IslandStyle.accentText)
                }
            } else if let upcoming = appState.upcomingEvent {
                upcomingRow(upcoming, emphasized: true)
            } else if appState.dayEvents.isEmpty {
                Text("Brak wydarzeń dzisiaj")
                    .font(.caption2)
                    .foregroundStyle(IslandStyle.tertiaryText)
            } else {
                ForEach(appState.dayEvents) { event in
                    if event.id != appState.upcomingEvent?.id {
                        upcomingRow(event, emphasized: false)
                    }
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private func upcomingRow(_ event: CalendarEventPreview, emphasized: Bool) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(emphasized ? .caption.weight(.semibold) : .caption)
                    .foregroundStyle(IslandStyle.primaryText)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(event.formattedStartTime)
                        .font(.caption2.monospacedDigit())
                    Text(event.formattedCountdown)
                        .font(.caption2)
                }
                .foregroundStyle(IslandStyle.tertiaryText)
            }

            Spacer(minLength: 0)

            if let meetingURL = event.meetingURL {
                Button {
                    NSWorkspace.shared.open(meetingURL)
                } label: {
                    Image(systemName: "video.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(IslandStyle.accentText)
                        .frame(width: 24, height: 24)
                        .background {
                            Circle().fill(Color.white.opacity(0.08))
                        }
                }
                .buttonStyle(.plain)
                .help("Otwórz spotkanie")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(emphasized ? 0.08 : 0.05))
        }
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
