import SwiftUI

@MainActor
struct FocusTabView: View {
    @Bindable var appState: AppState

    @State private var pickerMode: FocusPickerMode = .countdown
    @State private var draftMinutes = 25
    @State private var pulse = false

    private var state: FocusTimerState {
        appState.focusTimerState
    }

    private var accent: Color {
        appState.settings.selectedTheme.accent
    }

    var body: some View {
        VStack(spacing: 8) {
            modeStrip

            FocusTimerArcDisplay(
                time: displayedTime,
                progress: displayedProgress,
                modeLabel: state.mode == .idle ? pickerMode.title : state.modeLabel,
                isRunning: state.isRunning,
                accent: accent,
                pulse: pulse
            )
            .frame(height: 68)

            if showsRuler {
                FocusTimeRuler(
                    minutes: $draftMinutes,
                    accent: accent,
                    isEnabled: canEditDuration
                )
            } else if pickerMode == .pomodoro {
                pomodoroPhaseRow
            }

            controlRow
        }
        .onAppear {
            syncDraftFromState()
            syncPickerMode()
        }
        .onChange(of: state.mode) { _, _ in
            syncDraftFromState()
            syncPickerMode()
        }
        .onChange(of: state.selectedPresetMinutes) { _, _ in
            if state.mode == .idle {
                draftMinutes = state.selectedPresetMinutes
            }
        }
        .onChange(of: pickerMode) { _, _ in
            if state.mode == .idle {
                draftMinutes = pickerMode == .countdown ? state.selectedPresetMinutes : 0
            }
        }
        .onChange(of: state.isRunning) { _, running in
            pulse = running
        }
        .onChange(of: draftMinutes) { _, minutes in
            if canEditDuration {
                appState.focusTimerManager.selectDuration(minutes: minutes)
            }
        }
    }

    private var canEditDuration: Bool {
        pickerMode == .countdown && state.mode == .idle
    }

    private var showsRuler: Bool {
        pickerMode == .countdown && state.mode != .stopwatch
    }

    private var displayedTime: String {
        if state.mode == .idle {
            switch pickerMode {
            case .stopwatch:
                return "00:00"
            case .pomodoro:
                return "25:00"
            case .countdown:
                return formatMinutes(draftMinutes)
            }
        }
        return state.formattedTime
    }

    private var displayedProgress: Double {
        state.mode == .idle ? 0 : state.progress
    }

    private func formatMinutes(_ minutes: Int) -> String {
        String(format: "%02d:00", minutes)
    }

    private func syncDraftFromState() {
        if state.mode == .idle {
            draftMinutes = state.selectedPresetMinutes
        }
    }

    private var modeStrip: some View {
        HStack(spacing: 4) {
            ForEach(FocusPickerMode.allCases) { mode in
                modeChip(mode)
            }
        }
        .padding(3)
        .background {
            Capsule()
                .fill(Color.white.opacity(0.06))
        }
    }

    @ViewBuilder
    private func modeChip(_ mode: FocusPickerMode) -> some View {
        let isSelected = pickerMode == mode
        let isLocked = mode == .pomodoro && !appState.isPremium

        Button {
            guard !isLocked else { return }
            pickerMode = mode
            appState.focusTimerManager.reset()
            switch mode {
            case .countdown:
                draftMinutes = state.selectedPresetMinutes
                appState.focusTimerManager.selectDuration(minutes: draftMinutes)
            case .stopwatch, .pomodoro:
                draftMinutes = 0
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: mode.icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(mode.title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(isSelected ? Color.black.opacity(0.88) : IslandStyle.secondaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                if isSelected {
                    Capsule().fill(Color.white)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(.white.opacity(0.35))
                        .offset(x: 2, y: -2)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
    }

    private var pomodoroPhaseRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "leaf.fill")
                .font(.caption)
                .foregroundStyle(accent)
            Text(pomodoroHint)
                .font(.caption.weight(.medium))
                .foregroundStyle(IslandStyle.secondaryText)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
        }
    }

    private var pomodoroHint: String {
        switch state.mode {
        case .pomodoroBreak: loc("Time for a break — breathe")
        case .pomodoroWork: loc("Focus session in progress")
        default: loc("25 min work · 5 min break")
        }
    }

    private var controlRow: some View {
        HStack(spacing: 10) {
            Button(action: primaryAction) {
                HStack(spacing: 6) {
                    Image(systemName: primaryIcon)
                        .font(.system(size: 11, weight: .bold))
                    Text(primaryTitle)
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(Color.black.opacity(0.9))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.95), accent.opacity(0.75)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: accent.opacity(state.isRunning ? 0.35 : 0.15), radius: state.isRunning ? 8 : 4, y: 2)
                }
            }
            .buttonStyle(.plain)

            Button {
                appState.focusTimerManager.reset()
                draftMinutes = 25
                appState.focusTimerManager.selectDuration(minutes: draftMinutes)
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(IslandStyle.secondaryText)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
    }

    private var primaryIcon: String {
        state.isRunning ? "pause.fill" : "play.fill"
    }

    private var primaryTitle: String {
        if state.mode == .idle {
            return pickerMode == .stopwatch ? loc("Start stopwatch") : loc("Start")
        }
        return state.isRunning ? loc("Pause") : loc("Resume")
    }

    private func primaryAction() {
        switch pickerMode {
        case .countdown:
            if state.mode == .idle {
                appState.focusTimerManager.startCountdown(minutes: draftMinutes)
            } else {
                appState.focusTimerManager.toggle()
            }
        case .stopwatch:
            if state.mode != .stopwatch {
                appState.focusTimerManager.startStopwatch()
            } else {
                appState.focusTimerManager.toggle()
            }
        case .pomodoro:
            if state.mode == .idle {
                appState.focusTimerManager.startPomodoro()
            } else {
                appState.focusTimerManager.toggle()
            }
        }
    }

    private func syncPickerMode() {
        switch state.mode {
        case .stopwatch:
            pickerMode = .stopwatch
        case .pomodoroWork, .pomodoroBreak:
            pickerMode = .pomodoro
        case .countdown, .idle:
            if pickerMode == .stopwatch && state.mode == .idle { return }
            if pickerMode != .pomodoro {
                pickerMode = .countdown
            }
        }
    }
}

private enum FocusPickerMode: String, CaseIterable, Identifiable {
    case countdown
    case stopwatch
    case pomodoro

    var id: String { rawValue }

    var title: String {
        switch self {
        case .countdown: loc("Timer")
        case .stopwatch: loc("Stopwatch")
        case .pomodoro: loc("Pomodoro")
        }
    }

    var icon: String {
        switch self {
        case .countdown: "hourglass"
        case .stopwatch: "stopwatch"
        case .pomodoro: "leaf.fill"
        }
    }
}

// MARK: - Arc display

private struct FocusTimerArcDisplay: View {
    let time: String
    let progress: Double
    let modeLabel: String
    let isRunning: Bool
    let accent: Color
    let pulse: Bool

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height + 12)
            let lineWidth: CGFloat = 4

            ZStack {
                ArcShape(start: 0.12, end: 0.88)
                    .stroke(Color.white.opacity(0.07), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

                ArcShape(start: 0.12, end: 0.12 + 0.76 * progress)
                    .stroke(
                        accent,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .shadow(color: accent.opacity(isRunning ? 0.4 : 0.15), radius: isRunning ? 5 : 2)

                VStack(spacing: 1) {
                    Text(time)
                        .font(.system(size: 28, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(IslandStyle.primaryText)
                        .scaleEffect(pulse && isRunning ? 1.02 : 1)
                        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse && isRunning)

                    Text(modeLabel.uppercased())
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(accent.opacity(0.85))
                }
                .offset(y: 2)
            }
            .frame(width: size, height: size * 0.68)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct ArcShape: Shape {
    var start: Double
    var end: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = min(rect.width, rect.height)
        let center = CGPoint(x: rect.midX, y: w * 0.50)
        let radius = w / 2 - 6
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .radians(.pi + start * .pi),
            endAngle: .radians(.pi + end * .pi),
            clockwise: false
        )
        return path
    }
}
