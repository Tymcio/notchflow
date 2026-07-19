import AppKit
import SwiftUI

struct IdleLiveActivityView: View {
    let activity: LiveActivityKind
    let mediaState: MediaPlaybackState
    let accent: Color
    let wingLayout: IdleWingLayout
    let onAnswerCall: () -> Void
    let onDeclineCall: () -> Void
    let onEndCall: () -> Void
    var onOpenNotification: () -> Void = {}
    var onReplyNotification: (String) -> Void = { _ in }
    var onDismissFinishedTimer: () -> Void = {}
    var supportsQuickReply: Bool = false

    var body: some View {
        switch activity {
        case .incomingCall:
            // Incoming calls render via IncomingCallBannerView in NotchIslandView.
            EmptyView()
        case .activeCall(let call):
            let displayName = NotificationAppCatalog.isSystemCallUILabel(call.callerName)
                ? loc("Incoming call")
                : call.callerName
            IdleCallView(
                callerName: displayName,
                startedAt: call.startedAt,
                wingLayout: wingLayout,
                showsActions: true,
                onAnswer: {},
                onDecline: {},
                onEnd: onEndCall
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

    @State private var pulse = false

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
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let formattedTime = displayTime(at: context.date)
            let progress = displayProgress(at: context.date)

            IdleWingContainer(
                wingLayout: wingLayout,
                leading: {
                    ZStack {
                        if timer.isFinished {
                            Circle()
                                .fill(alertTint.opacity(isMutedAlert ? 0.4 : 0.28))
                                .frame(
                                    width: pulse ? (isMutedAlert ? 28 : 24) : 16,
                                    height: pulse ? (isMutedAlert ? 28 : 24) : 16
                                )
                                .animation(
                                    .easeInOut(duration: pulseDuration).repeatForever(autoreverses: true),
                                    value: pulse
                                )
                        }
                        Circle()
                            .stroke(IslandStyle.surfaceStroke, lineWidth: 2)
                            .frame(width: 20, height: 20)
                        Circle()
                            .trim(from: 0, to: timer.isFinished ? 1 : progress)
                            .stroke(alertTint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 20, height: 20)
                            .opacity(timer.isFinished ? (pulse ? 1 : 0.45) : 1)
                            .animation(
                                timer.isFinished
                                    ? .easeInOut(duration: pulseDuration).repeatForever(autoreverses: true)
                                    : .default,
                                value: pulse
                            )
                        Image(systemName: leadingSymbol)
                            .font(.system(size: isMutedAlert ? 9 : 8, weight: .bold))
                            .foregroundStyle(alertTint)
                            .scaleEffect(timer.isFinished && pulse ? (isMutedAlert ? 1.22 : 1.15) : 1)
                            .animation(
                                timer.isFinished
                                    ? .easeInOut(duration: pulseDuration).repeatForever(autoreverses: true)
                                    : .default,
                                value: pulse
                            )
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
                        .opacity(pulse ? 1 : 0.55)
                        .shadow(color: alertTint.opacity(0.55), radius: 6)
                        .animation(
                            .easeInOut(duration: pulseDuration).repeatForever(autoreverses: true),
                            value: pulse
                        )
                    } else {
                        Text(formattedTime)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(
                                timer.isFinished || timer.isRunning ? accent : IslandStyle.primaryText
                            )
                            .opacity(timer.isFinished ? (pulse ? 1 : 0.55) : 1)
                            .shadow(
                                color: (timer.isRunning || timer.isFinished) ? accent.opacity(timer.isFinished ? 0.55 : 0.35) : .clear,
                                radius: timer.isFinished ? 6 : 4
                            )
                            .animation(
                                timer.isFinished
                                    ? .easeInOut(duration: pulseDuration).repeatForever(autoreverses: true)
                                    : .default,
                                value: pulse
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
        .onAppear { pulse = timer.isFinished }
        .onChange(of: timer.isFinished) { _, finished in
            pulse = finished
        }
        .onChange(of: timer.isAlertMuted) { _, _ in
            pulse = timer.isFinished
        }
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

enum IdleCallMetrics {
    static let callerFontSize: CGFloat = 10
    static let subtitleFontSize: CGFloat = 9
    static let textLeadingPadding: CGFloat = 8
    static let trailingPadding: CGFloat = 10
    private static let actionButtonWidth: CGFloat = 24
    private static let actionButtonSpacing: CGFloat = 4

    @MainActor
    static func preferredRightWingWidth(
        callerName: String,
        actionButtonCount: Int,
        showsSubtitle: Bool = true
    ) -> CGFloat {
        let callerWidth = width(of: callerName, font: .systemFont(ofSize: callerFontSize, weight: .semibold))
        var total = callerWidth + textLeadingPadding + NotchFlowConstants.idleWingInnerOverlap
        if showsSubtitle {
            let subtitleWidth = width(of: loc("Incoming call"), font: .systemFont(ofSize: subtitleFontSize))
            total = max(total, subtitleWidth + textLeadingPadding + NotchFlowConstants.idleWingInnerOverlap)
        }
        if actionButtonCount > 0 {
            let count = CGFloat(actionButtonCount)
            total += count * actionButtonWidth + max(0, count - 1) * actionButtonSpacing + trailingPadding + 8
        } else {
            total += trailingPadding
        }
        return min(
            max(NotchFlowConstants.idleWingProtrusion, total.rounded(.up)),
            NotchFlowConstants.maxIdleCallWingWidth
        )
    }

    private static func width(of text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }
}

struct IdleCallView: View {
    let callerName: String
    var subtitle: String?
    var startedAt: Date?
    let wingLayout: IdleWingLayout
    let showsActions: Bool
    let onAnswer: () -> Void
    let onDecline: () -> Void
    let onEnd: () -> Void

    @State private var pulse = false

    private var isIncoming: Bool { startedAt == nil }

    var body: some View {
        Group {
            if startedAt != nil {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    callChrome(at: context.date)
                }
            } else {
                callChrome(at: .now)
            }
        }
    }

    @ViewBuilder
    private func callChrome(at date: Date) -> some View {
        IdleWingContainer(
            wingLayout: wingLayout,
            leading: {
                ZStack {
                    if isIncoming {
                        Circle()
                            .fill(Color.green.opacity(0.25))
                            .frame(width: pulse ? 22 : 16, height: pulse ? 22 : 16)
                            .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: pulse)
                    } else {
                        Circle()
                            .fill(Color.green.opacity(0.2))
                            .frame(width: 18, height: 18)
                    }
                    Image(systemName: "phone.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.green)
                }
                .onAppear { pulse = isIncoming }
            },
            trailing: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(callerName)
                            .font(.system(size: IdleCallMetrics.callerFontSize, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        if showsSecondaryLine {
                            Text(displaySubtitle(at: date))
                                .font(.system(size: IdleCallMetrics.subtitleFontSize))
                                .foregroundStyle(IslandStyle.secondaryText)
                                .lineLimit(1)
                                .monospacedDigit()
                        }
                    }
                    .padding(.leading, NotchFlowConstants.idleWingInnerOverlap + IdleCallMetrics.textLeadingPadding)

                    if showsActions {
                        HStack(spacing: 4) {
                            if isIncoming {
                                callButton(
                                    systemImage: "phone.down.fill",
                                    label: loc("Decline call"),
                                    tint: .red,
                                    action: onDecline
                                )
                                callButton(
                                    systemImage: "phone.fill",
                                    label: loc("Answer call"),
                                    tint: .green,
                                    action: onAnswer
                                )
                            } else {
                                callButton(
                                    systemImage: "phone.down.fill",
                                    label: loc("End call"),
                                    tint: .red,
                                    action: onEnd
                                )
                            }
                        }
                        .padding(.trailing, IdleCallMetrics.trailingPadding)
                    }
                }
                .foregroundStyle(IslandStyle.primaryText)
            }
        )
    }

    private var showsSecondaryLine: Bool {
        if startedAt != nil { return true }
        if let subtitle, !subtitle.isEmpty { return true }
        return false
    }

    private func displaySubtitle(at date: Date) -> String {
        if let subtitle {
            return subtitle
        }
        if let startedAt {
            let total = max(0, Int(date.timeIntervalSince(startedAt)))
            let minutes = total / 60
            let seconds = total % 60
            return String(format: "%d:%02d", minutes, seconds)
        }
        return ""
    }

    @ViewBuilder
    private func callButton(
        systemImage: String,
        label: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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
