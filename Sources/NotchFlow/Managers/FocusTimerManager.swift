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
    /// True when the finish alert could not be heard (system mute / volume 0).
    var isAlertMuted = false
    /// Default output is muted or at zero volume right now (kept live by a CoreAudio listener).
    var isOutputSilent = false

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
        case .idle: loc("Timer")
        case .countdown: loc("Timer")
        case .pomodoroWork: loc("Focus")
        case .pomodoroBreak: loc("Break")
        case .stopwatch: loc("Stopwatch")
        }
    }

    var showsInIdleNotch: Bool {
        mode != .idle && (isRunning || remainingSeconds != totalSeconds || elapsedSeconds > 0)
    }

    /// Countdown finished and waiting to be dismissed (stays at 00:00 in the idle notch).
    var isFinished: Bool {
        !isRunning && remainingSeconds == 0 && mode == .countdown
    }

    var activity: FocusTimerActivity {
        FocusTimerActivity(
            formattedTime: formattedTime,
            progress: progress,
            isRunning: isRunning,
            isFinished: isFinished,
            isAlertMuted: isAlertMuted,
            modeLabel: modeLabel,
            phaseEndDate: phaseEndDate,
            stopwatchStartDate: stopwatchStartDate,
            totalSeconds: totalSeconds,
            mode: mode
        )
    }
}

/// Countdown / Pomodoro / stopwatch state. Time is derived from `phaseEndDate` and
/// `stopwatchStartDate`; views tick their own display, so the manager only wakes once per
/// phase end (one-shot timer) instead of every second.
@MainActor
final class FocusTimerManager {
    var onStateChange: ((FocusTimerState) -> Void)?

    private(set) var state = FocusTimerState() {
        didSet {
            guard state != oldValue else { return }
            onStateChange?(state)
        }
    }

    private var phaseEndTimer: Timer?
    private let outputMonitor = OutputMuteMonitor()
    /// Sound to start once output is audible again (finished countdown while muted).
    private var pendingAlertSound: (id: String, loops: Bool)?
    private var attentionRequestID: Int?
    private var wakeObserver: NSObjectProtocol?

    var workDurationSeconds = 25 * 60
    var shortBreakSeconds = 5 * 60
    var longBreakSeconds = 15 * 60
    var sessionsBeforeLongBreak = 4

    func startMonitoring() {
        requestNotificationPermission()
        if wakeObserver == nil {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.reconcileWallClock()
                }
            }
        }
        outputMonitor.onChange = { [weak self] silent in
            self?.handleOutputSilenceChange(silent)
        }
        outputMonitor.start()
        state.isOutputSilent = outputMonitor.isSilent
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
            cancelPhaseEndTimer()
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
        cancelPhaseEndTimer()
        pendingAlertSound = nil
        cancelUserAttention()
        TimerAlertSound.stop()
        state = FocusTimerState(
            selectedPresetMinutes: state.selectedPresetMinutes,
            isOutputSilent: state.isOutputSilent
        )
    }

    /// One timer per countdown / Pomodoro phase, fired at its end. The stopwatch needs none.
    private func startTimer() {
        cancelPhaseEndTimer()
        guard state.isRunning, state.mode != .stopwatch, let phaseEndDate = state.phaseEndDate else { return }
        let timer = Timer(fire: phaseEndDate, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.phaseEndTimerFired()
            }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        phaseEndTimer = timer
    }

    private func cancelPhaseEndTimer() {
        phaseEndTimer?.invalidate()
        phaseEndTimer = nil
    }

    private func phaseEndTimerFired() {
        phaseEndTimer = nil
        reconcileWallClock()
        // Fired a little early (tolerance / clock change): wait for the real end.
        if state.isRunning, phaseEndTimer == nil {
            startTimer()
        }
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
            finishCountdown(title: loc("Timer finished"), body: loc("Time is up."))
        case .pomodoroWork:
            state.completedPomodoroSessions += 1
            let useLongBreak = state.completedPomodoroSessions.isMultiple(of: sessionsBeforeLongBreak)
            state.mode = .pomodoroBreak
            state.totalSeconds = useLongBreak ? longBreakSeconds : shortBreakSeconds
            state.remainingSeconds = state.totalSeconds
            state.isRunning = true
            state.phaseEndDate = Date().addingTimeInterval(TimeInterval(state.remainingSeconds))
            startTimer()
            postTimerAlert(
                title: loc("Break"),
                body: useLongBreak ? loc("Long break.") : loc("Short break."),
                loops: false
            )
        case .pomodoroBreak:
            state.mode = .pomodoroWork
            state.totalSeconds = workDurationSeconds
            state.remainingSeconds = workDurationSeconds
            state.isRunning = true
            state.phaseEndDate = Date().addingTimeInterval(TimeInterval(state.remainingSeconds))
            startTimer()
            postTimerAlert(title: loc("Focus"), body: loc("Next Pomodoro session."), loops: false)
        case .stopwatch, .idle:
            break
        }
    }

    private func finishCountdown(title: String, body: String) {
        state.isRunning = false
        cancelPhaseEndTimer()
        // Loop until the user dismisses the finished 00:00 state.
        postTimerAlert(title: title, body: body, loops: true)
    }

    private func postTimerAlert(title: String, body: String, loops: Bool) {
        let soundID = NotchSettings.shared.timerAlertSoundName
        let wantsSound = !soundID.isEmpty
        let muted = wantsSound && SystemOutputAudio.isSilent

        if muted {
            // Inaudible over mute — bounce Dock / flash; finished countdown also waits for unmute.
            TimerAlertSound.stop()
            state.isAlertMuted = loops // Persist for finished-countdown idle UI.
            requestUserAttention()
            // Start the looping alert as soon as output becomes audible (CoreAudio listener).
            pendingAlertSound = loops ? (soundID, true) : nil
            NotificationService.post(
                title: title,
                body: loc("Sound is muted — turn up volume to hear the alert."),
                sound: false
            )
        } else {
            state.isAlertMuted = false
            pendingAlertSound = nil
            cancelUserAttention()
            TimerAlertSound.play(soundID, loops: loops)
            NotificationService.post(title: title, body: body, sound: false)
        }
    }

    private func handleOutputSilenceChange(_ silent: Bool) {
        state.isOutputSilent = silent
        guard !silent, let pending = pendingAlertSound else { return }
        pendingAlertSound = nil
        // Dismissed / reset while waiting.
        guard state.isFinished, state.isAlertMuted else { return }
        state.isAlertMuted = false
        cancelUserAttention()
        TimerAlertSound.play(pending.id, loops: pending.loops)
    }

    private func requestUserAttention() {
        cancelUserAttention()
        attentionRequestID = NSApp.requestUserAttention(.criticalRequest)
    }

    private func cancelUserAttention() {
        if let attentionRequestID {
            NSApp.cancelUserAttentionRequest(attentionRequestID)
            self.attentionRequestID = nil
        }
    }

    private func requestNotificationPermission() {
        NotificationService.requestAuthorization()
    }
}
