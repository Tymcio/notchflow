import AppKit
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
    var phaseEndDate: Date?
    var stopwatchStartDate: Date?

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

    func formattedTime(at date: Date) -> String {
        switch mode {
        case .stopwatch:
            let elapsed = elapsedSeconds(at: date)
            let minutes = elapsed / 60
            let seconds = elapsed % 60
            return String(format: "%02d:%02d", minutes, seconds)
        default:
            let remaining = remainingSeconds(at: date)
            let minutes = remaining / 60
            let seconds = remaining % 60
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

    func progress(at date: Date) -> Double {
        switch mode {
        case .stopwatch:
            return min(1, Double(elapsedSeconds(at: date)) / 3600)
        case .idle:
            return 0
        default:
            guard totalSeconds > 0 else { return 0 }
            let remaining = remainingSeconds(at: date)
            return 1 - (Double(remaining) / Double(totalSeconds))
        }
    }

    func remainingSeconds(at date: Date) -> Int {
        if isRunning, let phaseEndDate {
            return max(0, Int(phaseEndDate.timeIntervalSince(date).rounded(.up)))
        }
        return remainingSeconds
    }

    func elapsedSeconds(at date: Date) -> Int {
        if isRunning, let stopwatchStartDate {
            return max(0, Int(date.timeIntervalSince(stopwatchStartDate)))
        }
        return elapsedSeconds
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
            modeLabel: modeLabel,
            phaseEndDate: phaseEndDate,
            stopwatchStartDate: stopwatchStartDate,
            totalSeconds: totalSeconds,
            mode: mode
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
    private var wakeObserver: NSObjectProtocol?

    var workDurationSeconds = 25 * 60
    var shortBreakSeconds = 5 * 60
    var longBreakSeconds = 15 * 60
    var sessionsBeforeLongBreak = 4

    deinit {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    func startMonitoring() {
        requestNotificationPermission()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reconcileWallClock()
        }
    }

    func selectDuration(minutes: Int) {
        let clamped = max(1, min(minutes, 180))
        state.selectedPresetMinutes = clamped
        guard state.mode == .idle || state.mode == .countdown else { return }
        state.totalSeconds = clamped * 60
        state.remainingSeconds = clamped * 60
        state.phaseEndDate = nil
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
        state.phaseEndDate = Date().addingTimeInterval(TimeInterval(state.remainingSeconds))
        state.stopwatchStartDate = nil
        startTimer()
    }

    func startPomodoro() {
        state.mode = .pomodoroWork
        state.totalSeconds = workDurationSeconds
        state.remainingSeconds = workDurationSeconds
        state.isRunning = true
        state.phaseEndDate = Date().addingTimeInterval(TimeInterval(state.remainingSeconds))
        state.stopwatchStartDate = nil
        startTimer()
    }

    func startStopwatch() {
        state.mode = .stopwatch
        state.elapsedSeconds = 0
        state.isRunning = true
        state.stopwatchStartDate = Date()
        state.phaseEndDate = nil
        startTimer()
    }

    func toggle() {
        guard state.mode != .idle else {
            startCountdown()
            return
        }

        if state.isRunning {
            reconcileWallClock()
            state.isRunning = false
            state.phaseEndDate = nil
            state.stopwatchStartDate = nil
            timer?.invalidate()
            timer = nil
        } else {
            state.isRunning = true
            switch state.mode {
            case .stopwatch:
                state.stopwatchStartDate = Date().addingTimeInterval(-TimeInterval(state.elapsedSeconds))
                state.phaseEndDate = nil
            case .countdown, .pomodoroWork, .pomodoroBreak:
                state.phaseEndDate = Date().addingTimeInterval(TimeInterval(state.remainingSeconds))
                state.stopwatchStartDate = nil
            case .idle:
                break
            }
            startTimer()
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
            self?.tick()
        }
    }

    private func tick() {
        reconcileWallClock()
    }

    private func reconcileWallClock() {
        guard state.isRunning else { return }

        switch state.mode {
        case .stopwatch:
            guard let stopwatchStartDate = state.stopwatchStartDate else { return }
            state.elapsedSeconds = max(0, Int(Date().timeIntervalSince(stopwatchStartDate)))
        case .countdown, .pomodoroWork, .pomodoroBreak:
            guard let phaseEndDate = state.phaseEndDate else { return }
            let remaining = max(0, Int(phaseEndDate.timeIntervalSinceNow.rounded(.up)))
            if remaining <= 0 {
                completeCurrentPhase()
            } else {
                state.remainingSeconds = remaining
            }
        case .idle:
            break
        }
    }

    private func completeCurrentPhase() {
        switch state.mode {
        case .countdown:
            state.remainingSeconds = 0
            state.phaseEndDate = nil
            finishCountdown(title: "Minutnik zakończony", body: "Czas minął.")
        case .pomodoroWork:
            state.completedPomodoroSessions += 1
            let useLongBreak = state.completedPomodoroSessions.isMultiple(of: sessionsBeforeLongBreak)
            state.mode = .pomodoroBreak
            state.totalSeconds = useLongBreak ? longBreakSeconds : shortBreakSeconds
            state.remainingSeconds = state.totalSeconds
            state.isRunning = true
            state.phaseEndDate = Date().addingTimeInterval(TimeInterval(state.remainingSeconds))
            NotificationService.post(title: "Przerwa", body: useLongBreak ? "Dłuższa przerwa." : "Krótka przerwa.")
        case .pomodoroBreak:
            state.mode = .pomodoroWork
            state.totalSeconds = workDurationSeconds
            state.remainingSeconds = workDurationSeconds
            state.isRunning = true
            state.phaseEndDate = Date().addingTimeInterval(TimeInterval(state.remainingSeconds))
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
