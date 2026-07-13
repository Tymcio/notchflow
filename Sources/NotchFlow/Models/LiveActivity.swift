import Foundation

struct IncomingCallActivity: Equatable, Sendable {
    let callerName: String
    let appBundleID: String
    let receivedAt: Date
}

struct ActiveCallActivity: Equatable, Sendable {
    let callerName: String
    let appBundleID: String
    let startedAt: Date

    var elapsedSeconds: Int {
        max(0, Int(Date().timeIntervalSince(startedAt)))
    }

    var formattedDuration: String {
        let total = elapsedSeconds
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct FocusTimerActivity: Equatable, Sendable {
    let formattedTime: String
    let progress: Double
    let isRunning: Bool
    let modeLabel: String
    let phaseEndDate: Date?
    let stopwatchStartDate: Date?
    let totalSeconds: Int
    let mode: FocusTimerMode

    init(
        formattedTime: String,
        progress: Double,
        isRunning: Bool,
        modeLabel: String,
        phaseEndDate: Date? = nil,
        stopwatchStartDate: Date? = nil,
        totalSeconds: Int = 0,
        mode: FocusTimerMode = .idle
    ) {
        self.formattedTime = formattedTime
        self.progress = progress
        self.isRunning = isRunning
        self.modeLabel = modeLabel
        self.phaseEndDate = phaseEndDate
        self.stopwatchStartDate = stopwatchStartDate
        self.totalSeconds = totalSeconds
        self.mode = mode
    }
}

struct NotificationPeekActivity: Equatable, Sendable {
    let id: UUID
    let appName: String
    let appBundleID: String
    let sender: String
    let body: String
    let receivedAt: Date
    let expiresAt: Date

    var isExpired: Bool {
        Date() >= expiresAt
    }
}

enum LiveActivityKind: Equatable, Sendable {
    case incomingCall(IncomingCallActivity)
    case activeCall(ActiveCallActivity)
    case timer(FocusTimerActivity)
    case notification(NotificationPeekActivity)
    case media

    var priority: Int {
        switch self {
        case .incomingCall: 0
        case .activeCall: 1
        case .timer: 2
        case .notification: 3
        case .media: 4
        }
    }
}

enum LiveActivityResolver {
    static func resolve(
        incomingCall: IncomingCallActivity?,
        activeCall: ActiveCallActivity?,
        timer: FocusTimerActivity?,
        notification: NotificationPeekActivity?,
        showsMedia: Bool
    ) -> LiveActivityKind? {
        if let incomingCall {
            return .incomingCall(incomingCall)
        }
        if let activeCall {
            return .activeCall(activeCall)
        }
        if let timer {
            return .timer(timer)
        }
        if let notification, !notification.isExpired {
            return .notification(notification)
        }
        if showsMedia {
            return .media
        }
        return nil
    }
}
