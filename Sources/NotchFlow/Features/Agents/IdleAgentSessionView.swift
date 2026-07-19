import AppKit
import SwiftUI

struct IdleAgentSessionView: View {
    let activity: AgentSessionActivity
    let accent: Color
    let wingLayout: IdleWingLayout
    var onAllow: (() -> Void)?
    var onDeny: (() -> Void)?
    var onJump: (() -> Void)?

    @State private var pulse = false

    private var needsAttention: Bool { activity.needsAttention }
    private var showsNotchApproval: Bool { activity.showsNotchApproval }

    var body: some View {
        IdleWingContainer(
            wingLayout: wingLayout,
            leading: {
                // Keep label in the visible petal — slot includes notch overlap on the trailing edge.
                HStack(spacing: 3) {
                    ZStack {
                        if needsAttention {
                            Circle()
                                .fill(Color.orange.opacity(0.32))
                                .frame(width: pulse ? 18 : 13, height: pulse ? 18 : 13)
                                .animation(
                                    .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                                    value: pulse
                                )
                        }
                        Image(systemName: activity.agent.systemImage)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(needsAttention ? Color.orange : accent)
                    }
                    .frame(width: 13, height: 13)

                    Text(activity.agent.compactDisplayName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(IslandStyle.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.leading, 5)
                .padding(.trailing, NotchFlowConstants.idleWingInnerOverlap)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { onJump?() }
                .onAppear { pulse = needsAttention }
                .onChange(of: needsAttention) { _, value in pulse = value }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(activity.agent.displayName)
                .accessibilityAddTraits(.isButton)
            },
            trailing: {
                Group {
                    if needsAttention, showsNotchApproval {
                        HStack(spacing: 4) {
                            agentButton(
                                systemImage: "xmark",
                                label: loc("Deny"),
                                fill: Color.red.opacity(0.9),
                                foreground: .white,
                                action: { onDeny?() }
                            )
                            agentButton(
                                systemImage: "checkmark",
                                label: loc("Allow"),
                                fill: Color.green,
                                foreground: .black.opacity(0.85),
                                action: { onAllow?() }
                            )
                        }
                        .padding(.trailing, 8)
                    } else if needsAttention {
                        // Cursor-style: approve in the agent — offer an obvious jump control.
                        Button {
                            onJump?()
                        } label: {
                            Image(systemName: "arrow.up.forward.app")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.orange)
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(Color.orange.opacity(0.18)))
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 10)
                        .accessibilityLabel(loc("Jump to agent"))
                    } else {
                        AgentTypingIndicator(color: accent)
                            .padding(.trailing, 10)
                            .accessibilityLabel(loc("Working…"))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { onJump?() }
            }
        )
    }

    @ViewBuilder
    private func agentButton(
        systemImage: String,
        label: String,
        fill: Color,
        foreground: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(foreground)
                .frame(width: 24, height: 24)
                .background(Circle().fill(fill))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Compact “agent is thinking / typing” indicator — not a music equalizer.
private struct AgentTypingIndicator: View {
    let color: Color
    @State private var bouncing = false

    var body: some View {
        HStack(spacing: 3.5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
                    .offset(y: bouncing ? -2.8 : 1.6)
                    .opacity(bouncing ? 1 : 0.35)
                    .animation(
                        .easeInOut(duration: 0.38)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.13),
                        value: bouncing
                    )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .onAppear { bouncing = true }
    }
}

enum IdleAgentMetrics {
    /// Room for icon + "Cursor" / "Claude" without sliding under the cutout.
    @MainActor
    static var preferredLeftWingWidth: CGFloat { 72 }

    /// Right petal widens for Allow/Deny or the jump control.
    @MainActor
    static func preferredRightWingWidth(needsAttention: Bool) -> CGFloat? {
        guard needsAttention else { return nil }
        let total = NotchFlowConstants.idleWingInnerOverlap + 56
        return min(
            max(NotchFlowConstants.idleWingProtrusion, CGFloat(total)),
            NotchFlowConstants.maxIdleCallWingWidth
        )
    }
}
