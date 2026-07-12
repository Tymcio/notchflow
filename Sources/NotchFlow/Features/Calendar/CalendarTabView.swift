import AppKit
import SwiftUI

struct CalendarTabView: View {
    @Bindable var appState: AppState
    @State private var visibleMonth = Date()
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var selectedDayEvents: [CalendarEventPreview] = []

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
        .task(id: selectedDay) {
            await reloadSelectedDayEvents()
        }
        .onChange(of: appState.calendarAccessGranted) { _, granted in
            guard granted else {
                selectedDayEvents = []
                return
            }
            Task { await reloadSelectedDayEvents() }
        }
    }

    @ViewBuilder
    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(selectedDayTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(IslandStyle.secondaryText)

            if !appState.calendarAccessGranted {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(IslandStyle.tertiaryText)
                    Text("Brak dostępu do kalendarza.")
                        .font(.caption2)
                        .foregroundStyle(IslandStyle.tertiaryText)
                    Spacer(minLength: 0)
                    Button("Udziel dostępu") {
                        requestCalendarAccess()
                    }
                    .font(.caption2.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(IslandStyle.accentText)
                    .contentShape(Rectangle())
                }
            } else if selectedDayEvents.isEmpty {
                Text("Brak wydarzeń w tym dniu")
                    .font(.caption2)
                    .foregroundStyle(IslandStyle.tertiaryText)
            } else {
                ForEach(selectedDayEvents) { event in
                    upcomingRow(event, emphasized: event.id == appState.upcomingEvent?.id)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }

    private var selectedDayTitle: String {
        if Calendar.current.isDateInToday(selectedDay) {
            return "Dzisiaj"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "d MMM"
        return formatter.string(from: selectedDay)
    }

    @ViewBuilder
    private func upcomingRow(_ event: CalendarEventPreview, emphasized: Bool) -> some View {
        Button {
            activatePanel()
            if let meetingURL = event.meetingURL {
                NSWorkspace.shared.open(meetingURL)
            } else {
                appState.calendarManager.openDayInCalendarApp(event.startDate)
            }
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(emphasized ? .caption.weight(.semibold) : .caption)
                        .foregroundStyle(IslandStyle.primaryText)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(event.formattedStartTime)
                            .font(.caption2.monospacedDigit())
                        if emphasized, event.startDate.timeIntervalSinceNow > 0 {
                            Text(event.formattedCountdown)
                                .font(.caption2)
                        }
                    }
                    .foregroundStyle(IslandStyle.tertiaryText)
                }

                Spacer(minLength: 0)

                Image(systemName: event.meetingURL == nil ? "calendar" : "video.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(IslandStyle.accentText)
                    .frame(width: 24, height: 24)
                    .background {
                        Circle().fill(Color.white.opacity(0.08))
                    }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(emphasized ? 0.08 : 0.05))
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(event.meetingURL == nil ? "Otwórz w Kalendarzu" : "Otwórz spotkanie")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                activatePanel()
                visibleMonth = MonthCalendarModel.previousMonth(from: visibleMonth)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(IslandStyle.secondaryText)

            Text(MonthCalendarModel.monthTitle(for: visibleMonth))
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)

            Button {
                activatePanel()
                visibleMonth = MonthCalendarModel.nextMonth(from: visibleMonth)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
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
        let isSelected = Calendar.current.isDate(day.date, inSameDayAs: selectedDay)
        let textColor: Color = {
            if isSelected { return Color.black.opacity(0.9) }
            if day.isToday { return Color.black.opacity(0.85) }
            if day.isCurrentMonth { return IslandStyle.primaryText }
            return IslandStyle.tertiaryText
        }()

        Button {
            selectDay(day)
        } label: {
            Text("\(day.number)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(textColor)
                .frame(width: 24, height: 24)
                .background {
                    if isSelected {
                        Circle().fill(Color.white.opacity(0.92))
                    } else if day.isToday {
                        Circle().stroke(Color.white.opacity(0.35), lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func activatePanel() {
        AppController.panelController?.prepareForTyping()
    }

    private func requestCalendarAccess() {
        activatePanel()
        Task {
            await appState.calendarManager.ensureAccess()
            appState.calendarAccessGranted = appState.calendarManager.hasAccess
            if appState.calendarManager.hasAccess {
                appState.calendarManager.startAutoRefresh()
            }
        }
    }

    private func selectDay(_ day: CalendarDay) {
        activatePanel()
        selectedDay = Calendar.current.startOfDay(for: day.date)
        if !day.isCurrentMonth {
            visibleMonth = day.date
        }
    }

    private func reloadSelectedDayEvents() async {
        guard appState.calendarAccessGranted else {
            selectedDayEvents = []
            return
        }
        selectedDayEvents = await appState.calendarManager.events(on: selectedDay)
    }
}
