import Foundation

struct FocusTimerActivity: Equatable, Sendable {
    let formattedTime: String
    let progress: Double
    let isRunning: Bool
    let isFinished: Bool
    let isAlertMuted: Bool
    let modeLabel: String
    let phaseEndDate: Date?
    let stopwatchStartDate: Date?
    let totalSeconds: Int
    let mode: FocusTimerMode

    init(
        formattedTime: String,
        progress: Double,
        isRunning: Bool,
        isFinished: Bool = false,
        isAlertMuted: Bool = false,
        modeLabel: String,
        phaseEndDate: Date? = nil,
        stopwatchStartDate: Date? = nil,
        totalSeconds: Int = 0,
        mode: FocusTimerMode = .idle
    ) {
        self.formattedTime = formattedTime
        self.progress = progress
        self.isRunning = isRunning
        self.isFinished = isFinished
        self.isAlertMuted = isAlertMuted
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
    let openBundleID: String
    let sender: String
    let body: String
    let receivedAt: Date
    let expiresAt: Date
    let supportsQuickReply: Bool

    var isExpired: Bool {
        Date() >= expiresAt
    }
}

enum LiveActivityKind: Equatable, Sendable {
    case agentSession(AgentSessionActivity)
    case timer(FocusTimerActivity)
    case notification(NotificationPeekActivity)
    /// A volume / brightness change, shown for a moment over media, timers and agents.
    case hud(HUDOverlayState)
    case media

    var priority: Int {
        switch self {
        case .agentSession(let session) where session.needsAttention: 2
        case .notification: 3
        case .hud: 4
        case .agentSession: 5
        case .timer: 6
        case .media: 7
        }
    }
}

enum LiveActivityResolver {
    static func resolve(
        agentSession: AgentSessionActivity?,
        timer: FocusTimerActivity?,
        notification: NotificationPeekActivity?,
        hud: HUDOverlayState? = nil,
        showsMedia: Bool,
        now: Date = Date()
    ) -> LiveActivityKind? {
        if let agentSession, agentSession.needsAttention {
            return .agentSession(agentSession)
        }
        // Transient notification peeks temporarily replace the focus timer in the island.
        if let notification, !notification.isExpired {
            return .notification(notification)
        }
        // Volume / brightness levels briefly replace whatever else sits in the wings; the
        // previous activity returns when the level expires.
        if let hud, hud.isActive(at: now) {
            return .hud(hud)
        }
        if let agentSession {
            return .agentSession(agentSession)
        }
        if let timer {
            return .timer(timer)
        }
        if showsMedia {
            return .media
        }
        return nil
    }
}
