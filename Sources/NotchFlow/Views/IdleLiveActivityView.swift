import AppKit
import SwiftUI

struct IdleLiveActivityView: View {
    let activity: LiveActivityKind
    let mediaState: MediaPlaybackState
    let accent: Color
    let wingLayout: IdleWingLayout
    var onOpenNotification: () -> Void = {}
    var onReplyNotification: (String) -> Void = { _ in }
    var onDismissFinishedTimer: () -> Void = {}
    var onAllowAgent: () -> Void = {}
    var onDenyAgent: () -> Void = {}
    var onJumpAgent: () -> Void = {}
    var supportsQuickReply: Bool = false
    var agentUsageHint: AgentUsageIdleHint?

    var body: some View {
        switch activity {
        case .agentSession(let session):
            IdleAgentSessionView(
                activity: session,
                accent: accent,
                wingLayout: wingLayout,
                onAllow: onAllowAgent,
                onDeny: onDenyAgent,
                onJump: onJumpAgent,
                usageHint: agentUsageHint
            )
        case .timer(let timer):
            IdleTimerView(
                timer: timer,
                accent: accent,
                wingLayout: wingLayout,
                onDismissFinished: onDismissFinishedTimer
            )
        case .notification:
            // Rendered as NotificationBannerView from NotchIslandView (hanging drip).
            EmptyView()
        case .hud(let hud):
            IdleHUDView(hud: hud, accent: accent, wingLayout: wingLayout)
        case .media:
            IdleMediaView(state: mediaState, wingLayout: wingLayout)
        }
    }
}

struct IdleTimerView: View {
    let timer: FocusTimerActivity
    let accent: Color
    let wingLayout: IdleWingLayout
    var onDismissFinished: () -> Void = {}

    private var isMutedAlert: Bool {
        timer.isFinished && timer.isAlertMuted
    }

    private var alertTint: Color {
        isMutedAlert ? Color.orange : accent
    }

    private var pulseDuration: Double {
        isMutedAlert ? 0.45 : 0.7
    }

    var body: some View {
        // Only a running timer needs a clock; finished / paused timers are static, and the
        // finished glow is a Core Animation pulse (render server, Reduce Motion aware).
        if timer.isRunning {
            TimelineView(.periodic(from: Self.tickAnchor(for: timer), by: 1)) { context in
                content(at: context.date)
            }
        } else {
            content(at: Date())
        }
    }

    /// A fixed date on the same sub-second grid as the moments the shown time changes.
    static func tickAnchor(for timer: FocusTimerActivity) -> Date {
        if let phaseEndDate = timer.phaseEndDate {
            return phaseEndDate.addingTimeInterval(-Double(max(timer.totalSeconds, 1)))
        }
        return timer.stopwatchStartDate ?? Date()
    }

    private func content(at date: Date) -> some View {
        let formattedTime = displayTime(at: date)
        let progress = displayProgress(at: date)

        return IdleWingContainer(
            wingLayout: wingLayout,
            leading: {
                ZStack {
                    if timer.isFinished {
                        PulseHaloView(
                            color: alertTint.opacity(isMutedAlert ? 0.4 : 0.28),
                            minDiameter: 16,
                            maxDiameter: isMutedAlert ? 28 : 24,
                            duration: pulseDuration
                        )
                        .frame(width: 28, height: 28)
                    }
                    Circle()
                        .stroke(IslandStyle.surfaceStroke, lineWidth: 2)
                        .frame(width: 20, height: 20)
                    Circle()
                        .trim(from: 0, to: timer.isFinished ? 1 : progress)
                        .stroke(alertTint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 20, height: 20)
                    Image(systemName: leadingSymbol)
                        .font(.system(size: isMutedAlert ? 9 : 8, weight: .bold))
                        .foregroundStyle(alertTint)
                }
            },
            trailing: {
                if isMutedAlert {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(formattedTime)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(alertTint)
                        Text(loc("Sound muted"))
                            .font(.system(size: IdleTimerMetrics.muteCaptionFontSize, weight: .medium))
                            .foregroundStyle(alertTint.opacity(0.9))
                            .lineLimit(1)
                    }
                    .padding(.leading, NotchFlowConstants.idleWingInnerOverlap + 4)
                    .shadow(color: alertTint.opacity(0.55), radius: 6)
                } else {
                    Text(formattedTime)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(
                            timer.isFinished || timer.isRunning ? accent : IslandStyle.primaryText
                        )
                        .shadow(
                            color: (timer.isRunning || timer.isFinished) ? accent.opacity(timer.isFinished ? 0.55 : 0.35) : .clear,
                            radius: timer.isFinished ? 6 : 4
                        )
                }
            }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard timer.isFinished else { return }
            onDismissFinished()
        }
        .accessibilityAddTraits(timer.isFinished ? .isButton : [])
        .accessibilityLabel(
            isMutedAlert
                ? "\(loc("Timer finished")), \(loc("Sound muted"))"
                : (timer.isFinished ? loc("Dismiss") : loc("Timer"))
        )
        .accessibilityHint(timer.isFinished ? loc("Dismiss") : "")
    }

    private var leadingSymbol: String {
        if isMutedAlert { return "speaker.slash.fill" }
        if timer.isFinished { return "bell.fill" }
        return timer.isRunning ? "hourglass.bottomhalf.filled" : "hourglass"
    }

    private func displayTime(at date: Date) -> String {
        switch timer.mode {
        case .stopwatch:
            if timer.isRunning, let startedAt = timer.stopwatchStartDate {
                let elapsed = max(0, Int(date.timeIntervalSince(startedAt)))
                let minutes = elapsed / 60
                let seconds = elapsed % 60
                return String(format: "%02d:%02d", minutes, seconds)
            }
            return timer.formattedTime
        default:
            if timer.isRunning, let phaseEndDate = timer.phaseEndDate {
                let remaining = max(0, Int(phaseEndDate.timeIntervalSince(date).rounded(.up)))
                let minutes = remaining / 60
                let seconds = remaining % 60
                return String(format: "%02d:%02d", minutes, seconds)
            }
            return timer.formattedTime
        }
    }

    private func displayProgress(at date: Date) -> Double {
        guard timer.totalSeconds > 0 || timer.mode == .stopwatch else { return timer.progress }
        switch timer.mode {
        case .stopwatch:
            if timer.isRunning, let startedAt = timer.stopwatchStartDate {
                let elapsed = max(0, Int(date.timeIntervalSince(startedAt)))
                return min(1, Double(elapsed) / 3600)
            }
            return timer.progress
        default:
            if timer.isRunning, let phaseEndDate = timer.phaseEndDate {
                let remaining = max(0, Int(phaseEndDate.timeIntervalSince(date).rounded(.up)))
                return 1 - (Double(remaining) / Double(timer.totalSeconds))
            }
            return timer.progress
        }
    }
}

enum IdleTimerMetrics {
    static let muteCaptionFontSize: CGFloat = 9

    @MainActor
    static func preferredMutedRightWingWidth() -> CGFloat {
        let timeWidth = width(of: "00:00", font: .systemFont(ofSize: 11, weight: .semibold))
        let captionWidth = width(
            of: loc("Sound muted"),
            font: .systemFont(ofSize: muteCaptionFontSize, weight: .medium)
        )
        let textWidth = max(timeWidth, captionWidth)
        let total = textWidth + NotchFlowConstants.idleWingInnerOverlap + 16
        return min(
            max(NotchFlowConstants.idleWingProtrusion, total.rounded(.up)),
            NotchFlowConstants.maxIdleCallWingWidth
        )
    }

    private static func width(of text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }
}

struct IdleWingContainer<Leading: View, Trailing: View>: View {
    let wingLayout: IdleWingLayout
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        IdleWingRow(
            layout: wingLayout,
            showsLeftWing: wingLayout.visibleLeftWidth > 0,
            showsRightWing: wingLayout.visibleRightWidth > 0,
            leading: leading,
            trailing: trailing
        )
    }
}
