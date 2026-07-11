import Foundation

enum FocusTimerMode: String, Sendable {
    case idle
    case countdown
    case pomodoroWork
    case pomodoroBreak
    case stopwatch
}

struct FocusTimerState: Equatable, Sendable {
    var mode: FocusTimerMode = .idle
    var isRunning = false
    var remainingSeconds = 25 * 60
    var elapsedSeconds = 0
    var totalSeconds = 25 * 60
    var completedPomodoroSessions = 0
    var selectedPresetMinutes = 25

    var formattedTime: String {
        switch mode {
        case .stopwatch:
            let minutes = elapsedSeconds / 60
            let seconds = elapsedSeconds % 60
            return String(format: "%02d:%02d", minutes, seconds)
        default:
            let minutes = remainingSeconds / 60
            let seconds = remainingSeconds % 60
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    var progress: Double {
        switch mode {
        case .stopwatch:
            return min(1, Double(elapsedSeconds) / 3600)
        case .idle:
            return 0
        default:
            guard totalSeconds > 0 else { return 0 }
            return 1 - (Double(remainingSeconds) / Double(totalSeconds))
        }
    }

    var modeLabel: String {
        switch mode {
        case .idle: "Minutnik"
        case .countdown: "Minutnik"
        case .pomodoroWork: "Skupienie"
        case .pomodoroBreak: "Przerwa"
        case .stopwatch: "Stoper"
        }
    }

    var showsInIdleNotch: Bool {
        mode != .idle && (isRunning || remainingSeconds != totalSeconds || elapsedSeconds > 0)
    }

    var activity: FocusTimerActivity {
        FocusTimerActivity(
            formattedTime: formattedTime,
            progress: progress,
            isRunning: isRunning,
            modeLabel: modeLabel
        )
    }
}

@MainActor
final class FocusTimerManager {
    var onStateChange: ((FocusTimerState) -> Void)?

    private(set) var state = FocusTimerState() {
        didSet { onStateChange?(state) }
    }

    private var timer: Timer?

    var workDurationSeconds = 25 * 60
    var shortBreakSeconds = 5 * 60
    var longBreakSeconds = 15 * 60
    var sessionsBeforeLongBreak = 4

    func startMonitoring() {
        requestNotificationPermission()
    }

    func selectDuration(minutes: Int) {
        let clamped = max(1, min(minutes, 180))
        state.selectedPresetMinutes = clamped
        guard state.mode == .idle || state.mode == .countdown else { return }
        state.totalSeconds = clamped * 60
        state.remainingSeconds = clamped * 60
    }

    func setPreset(minutes: Int) {
        selectDuration(minutes: minutes)
    }

    func startCountdown(minutes: Int? = nil) {
        if let minutes {
            selectDuration(minutes: minutes)
        } else if state.mode == .idle {
            selectDuration(minutes: state.selectedPresetMinutes)
        }
        state.mode = .countdown
        state.isRunning = true
        startTimer()
    }

    func startPomodoro() {
        state.mode = .pomodoroWork
        state.totalSeconds = workDurationSeconds
        state.remainingSeconds = workDurationSeconds
        state.isRunning = true
        startTimer()
    }

    func startStopwatch() {
        state.mode = .stopwatch
        state.elapsedSeconds = 0
        state.isRunning = true
        startTimer()
    }

    func toggle() {
        guard state.mode != .idle else {
            startCountdown()
            return
        }

        state.isRunning.toggle()
        if state.isRunning {
            startTimer()
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    func reset() {
        timer?.invalidate()
        timer = nil
        state = FocusTimerState(selectedPresetMinutes: state.selectedPresetMinutes)
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func tick() {
        switch state.mode {
        case .stopwatch:
            state.elapsedSeconds += 1
        case .countdown, .pomodoroWork, .pomodoroBreak:
            guard state.remainingSeconds > 0 else {
                completeCurrentPhase()
                return
            }
            state.remainingSeconds -= 1
        case .idle:
            break
        }
    }

    private func completeCurrentPhase() {
        switch state.mode {
        case .countdown:
            finishCountdown(title: "Minutnik zakończony", body: "Czas minął.")
        case .pomodoroWork:
            state.completedPomodoroSessions += 1
            let useLongBreak = state.completedPomodoroSessions.isMultiple(of: sessionsBeforeLongBreak)
            state.mode = .pomodoroBreak
            state.totalSeconds = useLongBreak ? longBreakSeconds : shortBreakSeconds
            state.remainingSeconds = state.totalSeconds
            state.isRunning = true
            NotificationService.post(title: "Przerwa", body: useLongBreak ? "Dłuższa przerwa." : "Krótka przerwa.")
        case .pomodoroBreak:
            state.mode = .pomodoroWork
            state.totalSeconds = workDurationSeconds
            state.remainingSeconds = workDurationSeconds
            state.isRunning = true
            NotificationService.post(title: "Skupienie", body: "Kolejna sesja Pomodoro.")
        case .stopwatch, .idle:
            break
        }
    }

    private func finishCountdown(title: String, body: String) {
        state.isRunning = false
        timer?.invalidate()
        timer = nil
        NotificationService.post(title: title, body: body)
    }

    private func requestNotificationPermission() {
        NotificationService.requestAuthorization()
    }
}
