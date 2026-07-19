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

    var body: some View {
        IdleWingContainer(
            wingLayout: wingLayout,
            leading: {
                ZStack {
                    if needsAttention {
                        Circle()
                            .fill(Color.orange.opacity(0.28))
                            .frame(width: pulse ? 24 : 16, height: pulse ? 24 : 16)
                            .animation(
                                .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                                value: pulse
                            )
                    }
                    Image(systemName: activity.agent.systemImage)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(needsAttention ? Color.orange : accent)
                }
                .onAppear { pulse = needsAttention }
                .onChange(of: needsAttention) { _, value in pulse = value }
            },
            trailing: {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(activity.title)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Text(activity.agent.displayName)
                            .font(.system(size: 9))
                            .foregroundStyle(IslandStyle.secondaryText)
                            .lineLimit(1)
                    }
                    .padding(.leading, NotchFlowConstants.idleWingInnerOverlap + 6)
                    .contentShape(Rectangle())
                    .onTapGesture { onJump?() }

                    if needsAttention {
                        HStack(spacing: 4) {
                            agentButton(
                                systemImage: "xmark",
                                label: loc("Deny"),
                                tint: .red,
                                action: { onDeny?() }
                            )
                            agentButton(
                                systemImage: "checkmark",
                                label: loc("Allow"),
                                tint: .green,
                                action: { onAllow?() }
                            )
                        }
                        .padding(.trailing, 8)
                    }
                }
                .foregroundStyle(IslandStyle.primaryText)
            }
        )
    }

    @ViewBuilder
    private func agentButton(
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

enum IdleAgentMetrics {
    @MainActor
    static func preferredRightWingWidth(title: String, needsAttention: Bool) -> CGFloat {
        let titleWidth = (title as NSString)
            .size(withAttributes: [.font: NSFont.systemFont(ofSize: 10, weight: .semibold)])
            .width
        var total = titleWidth + NotchFlowConstants.idleWingInnerOverlap + 24
        if needsAttention {
            total += 56
        }
        return min(
            max(NotchFlowConstants.idleWingProtrusion, total.rounded(.up)),
            NotchFlowConstants.maxIdleCallWingWidth
        )
    }
}
