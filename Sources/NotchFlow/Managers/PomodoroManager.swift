import Foundation

struct PomodoroState: Equatable, Sendable {
    var isRunning = false
    var remainingSeconds = 25 * 60
    var completedSessions = 0

    var formattedTime: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

@MainActor
final class PomodoroManager {
    var onStateChange: ((PomodoroState) -> Void)?

    private(set) var state = PomodoroState() {
        didSet { onStateChange?(state) }
    }

    private var timer: Timer?

    func start() {
        requestNotificationPermission()
    }

    func toggle() {
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
        state.isRunning = false
        state.remainingSeconds = 25 * 60
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
        guard state.remainingSeconds > 0 else {
            completeSession()
            return
        }
        state.remainingSeconds -= 1
    }

    private func completeSession() {
        state.isRunning = false
        state.completedSessions += 1
        state.remainingSeconds = 25 * 60
        timer?.invalidate()
        timer = nil
        NotificationService.post(title: "Pomodoro Complete", body: "Time for a short break.")
    }

    private func requestNotificationPermission() {
        NotificationService.requestAuthorization()
    }
}
