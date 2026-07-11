import AppKit
import SwiftUI

struct IdleLiveActivityView: View {
    let activity: LiveActivityKind
    let mediaState: MediaPlaybackState
    let accent: Color
    let leftWingWidth: CGFloat
    let rightWingWidth: CGFloat
    let notchCutoutWidth: CGFloat
    let innerOverlap: CGFloat
    let onAnswerCall: () -> Void
    let onDeclineCall: () -> Void

    var body: some View {
        switch activity {
        case .incomingCall(let call):
            IdleCallView(
                callerName: call.callerName,
                subtitle: "Połączenie przychodzące",
                leftWingWidth: leftWingWidth,
                rightWingWidth: rightWingWidth,
                notchCutoutWidth: notchCutoutWidth,
                innerOverlap: innerOverlap,
                showsActions: true,
                onAnswer: onAnswerCall,
                onDecline: onDeclineCall
            )
        case .activeCall(let call):
            IdleCallView(
                callerName: call.callerName,
                subtitle: call.formattedDuration,
                leftWingWidth: leftWingWidth,
                rightWingWidth: rightWingWidth,
                notchCutoutWidth: notchCutoutWidth,
                innerOverlap: innerOverlap,
                showsActions: false,
                onAnswer: {},
                onDecline: {}
            )
        case .timer(let timer):
            IdleTimerView(
                timer: timer,
                accent: accent,
                leftWingWidth: leftWingWidth,
                rightWingWidth: rightWingWidth,
                notchCutoutWidth: notchCutoutWidth,
                innerOverlap: innerOverlap
            )
        case .notification(let notification):
            IdleNotificationView(
                notification: notification,
                leftWingWidth: leftWingWidth,
                rightWingWidth: rightWingWidth,
                notchCutoutWidth: notchCutoutWidth,
                innerOverlap: innerOverlap
            )
        case .media:
            IdleMediaView(
                state: mediaState,
                leftWingWidth: leftWingWidth,
                rightWingWidth: rightWingWidth,
                notchCutoutWidth: notchCutoutWidth,
                innerOverlap: innerOverlap
            )
        }
    }
}

struct IdleTimerView: View {
    let timer: FocusTimerActivity
    let accent: Color
    let leftWingWidth: CGFloat
    let rightWingWidth: CGFloat
    let notchCutoutWidth: CGFloat
    let innerOverlap: CGFloat

    var body: some View {
        IdleWingContainer(
            leftWingWidth: leftWingWidth,
            rightWingWidth: rightWingWidth,
            notchCutoutWidth: notchCutoutWidth,
            innerOverlap: innerOverlap,
            leading: {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 2)
                        .frame(width: 20, height: 20)
                    Circle()
                        .trim(from: 0, to: timer.progress)
                        .stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 20, height: 20)
                    Image(systemName: timer.isRunning ? "hourglass.bottomhalf.filled" : "hourglass")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(accent)
                }
            },
            trailing: {
                Text(timer.formattedTime)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(timer.isRunning ? accent : .white.opacity(0.92))
                    .shadow(color: timer.isRunning ? accent.opacity(0.35) : .clear, radius: 4)
            }
        )
    }
}

struct IdleNotificationView: View {
    let notification: NotificationPeekActivity
    let leftWingWidth: CGFloat
    let rightWingWidth: CGFloat
    let notchCutoutWidth: CGFloat
    let innerOverlap: CGFloat

    var body: some View {
        IdleWingContainer(
            leftWingWidth: leftWingWidth,
            rightWingWidth: rightWingWidth,
            notchCutoutWidth: notchCutoutWidth,
            innerOverlap: innerOverlap,
            leading: {
                appIcon
            },
            trailing: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(notification.sender)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                    Text(notification.body)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
            }
        )
    }

    @ViewBuilder
    private var appIcon: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: notification.appBundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 18, height: 18)
        } else {
            Image(systemName: "bell.fill")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

struct IdleCallView: View {
    let callerName: String
    let subtitle: String
    let leftWingWidth: CGFloat
    let rightWingWidth: CGFloat
    let notchCutoutWidth: CGFloat
    let innerOverlap: CGFloat
    let showsActions: Bool
    let onAnswer: () -> Void
    let onDecline: () -> Void

    @State private var pulse = false

    var body: some View {
        IdleWingContainer(
            leftWingWidth: leftWingWidth,
            rightWingWidth: rightWingWidth,
            notchCutoutWidth: notchCutoutWidth,
            innerOverlap: innerOverlap,
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
                        Text(subtitle)
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                    }

                    if showsActions {
                        HStack(spacing: 4) {
                            callButton(systemImage: "phone.down.fill", tint: .red, action: onDecline)
                            callButton(systemImage: "phone.fill", tint: .green, action: onAnswer)
                        }
                    }
                }
                .foregroundStyle(.white)
            }
        )
    }

    @ViewBuilder
    private func callButton(systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }
}

struct IdleWingContainer<Leading: View, Trailing: View>: View {
    let leftWingWidth: CGFloat
    let rightWingWidth: CGFloat
    let notchCutoutWidth: CGFloat
    let innerOverlap: CGFloat
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 0) {
            if leftWingWidth > 0 {
                idleWing(isLeading: true, content: leading)
                    .frame(width: leftWingWidth + innerOverlap)
            }

            Color.clear
                .frame(width: centerClearWidth)
                .allowsHitTesting(false)

            if rightWingWidth > 0 {
                idleWing(isLeading: false, content: trailing)
                    .frame(width: rightWingWidth + innerOverlap)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var centerClearWidth: CGFloat {
        let leftOverlap = leftWingWidth > 0 ? innerOverlap : 0
        let rightOverlap = rightWingWidth > 0 ? innerOverlap : 0
        return max(0, notchCutoutWidth - leftOverlap - rightOverlap)
    }

    @ViewBuilder
    private func idleWing<Content: View>(isLeading: Bool, @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                NotchWingShape(isLeading: isLeading)
                    .fill(.black)
            }
    }
}
