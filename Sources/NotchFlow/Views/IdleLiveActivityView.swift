import AppKit
import SwiftUI

struct IdleLiveActivityView: View {
    let activity: LiveActivityKind
    let mediaState: MediaPlaybackState
    let accent: Color
    let wingLayout: IdleWingLayout
    let onAnswerCall: () -> Void
    let onDeclineCall: () -> Void

    var body: some View {
        switch activity {
        case .incomingCall(let call):
            IdleCallView(
                callerName: call.callerName,
                subtitle: loc("Incoming call"),
                wingLayout: wingLayout,
                showsActions: true,
                onAnswer: onAnswerCall,
                onDecline: onDeclineCall
            )
        case .activeCall(let call):
            IdleCallView(
                callerName: call.callerName,
                startedAt: call.startedAt,
                wingLayout: wingLayout,
                showsActions: false,
                onAnswer: {},
                onDecline: {}
            )
        case .timer(let timer):
            IdleTimerView(timer: timer, accent: accent, wingLayout: wingLayout)
        case .notification(let notification):
            IdleNotificationView(notification: notification, wingLayout: wingLayout)
        case .media:
            IdleMediaView(state: mediaState, wingLayout: wingLayout)
        }
    }
}

struct IdleTimerView: View {
    let timer: FocusTimerActivity
    let accent: Color
    let wingLayout: IdleWingLayout

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let formattedTime = displayTime(at: context.date)
            let progress = displayProgress(at: context.date)

            IdleWingContainer(
                wingLayout: wingLayout,
                leading: {
                    ZStack {
                        Circle()
                            .stroke(IslandStyle.surfaceStroke, lineWidth: 2)
                            .frame(width: 20, height: 20)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 20, height: 20)
                        Image(systemName: timer.isRunning ? "hourglass.bottomhalf.filled" : "hourglass")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(accent)
                    }
                },
                trailing: {
                    Text(formattedTime)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(timer.isRunning ? accent : IslandStyle.primaryText)
                        .shadow(color: timer.isRunning ? accent.opacity(0.35) : .clear, radius: 4)
                }
            )
        }
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

struct IdleNotificationView: View {
    let notification: NotificationPeekActivity
    let wingLayout: IdleWingLayout

    var body: some View {
        IdleWingContainer(
            wingLayout: wingLayout,
            leading: {
                appIcon
            },
            trailing: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(notification.sender)
                        .font(.system(size: IdleNotificationMetrics.senderFontSize, weight: .semibold))
                        .lineLimit(1)
                    Text(notification.body)
                        .font(.system(size: IdleNotificationMetrics.bodyFontSize))
                        .foregroundStyle(IslandStyle.secondaryText)
                        .lineLimit(1)
                }
                .foregroundStyle(IslandStyle.primaryText)
                // Keep text out of the hidden overlap strip under the notch cutout.
                .padding(.leading, NotchFlowConstants.idleWingInnerOverlap + IdleNotificationMetrics.textLeadingPadding)
                .padding(.trailing, IdleNotificationMetrics.textTrailingPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        )
    }

    @ViewBuilder
    private var appIcon: some View {
        CatalogAppIcon(bundleID: notification.appBundleID)
    }
}

/// Sizes the right wing so a notification peek shows readable text instead of the fixed 54 pt ear.
enum IdleNotificationMetrics {
    static let senderFontSize: CGFloat = 10
    static let bodyFontSize: CGFloat = 9
    /// Gap between the notch edge and the first character.
    static let textLeadingPadding: CGFloat = 10
    static let textTrailingPadding: CGFloat = 14

    @MainActor
    static func preferredRightWingWidth(for notification: NotificationPeekActivity) -> CGFloat {
        let senderWidth = width(of: notification.sender, font: .systemFont(ofSize: senderFontSize, weight: .semibold))
        let bodyWidth = width(of: notification.body, font: .systemFont(ofSize: bodyFontSize))
        let total = (max(senderWidth, bodyWidth) + textLeadingPadding + textTrailingPadding).rounded(.up)
        return min(
            max(NotchFlowConstants.idleWingProtrusion, total),
            NotchFlowConstants.maxIdleNotificationWingWidth
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

    @State private var pulse = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            IdleWingContainer(
                wingLayout: wingLayout,
                leading: {
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.25))
                            .frame(width: pulse ? 22 : 16, height: pulse ? 22 : 16)
                            .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: pulse)
                        Image(systemName: "phone.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.green)
                    }
                    .onAppear { pulse = true }
                },
                trailing: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(callerName)
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(1)
                            Text(displaySubtitle(at: context.date))
                                .font(.system(size: 9))
                                .foregroundStyle(IslandStyle.secondaryText)
                                .lineLimit(1)
                        }

                        if showsActions {
                            HStack(spacing: 4) {
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
                            }
                        }
                    }
                    .foregroundStyle(IslandStyle.primaryText)
                }
            )
        }
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
