import SwiftUI

struct AgentUsageMetersView: View {
    let snapshots: [AgentUsageSnapshot]
    var isRefreshing: Bool = false
    var onRefresh: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(loc("Usage"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(IslandStyle.secondaryText)
                Spacer(minLength: 0)
                if let onRefresh {
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(IslandStyle.secondaryText)
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                            .animation(
                                isRefreshing
                                    ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                                    : .default,
                                value: isRefreshing
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isRefreshing)
                    .accessibilityLabel(loc("Refresh usage"))
                }
            }

            ForEach(displayedSnapshots, id: \.agent) { snapshot in
                providerCard(snapshot)
            }
        }
    }

    private var displayedSnapshots: [AgentUsageSnapshot] {
        let preferred: [AgentKind] = [.claude, .codex]
        return preferred.compactMap { kind in
            snapshots.first(where: { $0.agent == kind })
        }
    }

    @ViewBuilder
    private func providerCard(_ snapshot: AgentUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(snapshot.agent.compactDisplayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(IslandStyle.primaryText)
                if let plan = snapshot.planName, !plan.isEmpty {
                    Text(plan)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(IslandStyle.tertiaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            if snapshot.hasMeters {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(alignment: .leading, spacing: 6) {
                        if let fiveHour = snapshot.fiveHour {
                            meterRow(label: loc("5h"), window: fiveHour, now: context.date)
                        }
                        if let sevenDay = snapshot.sevenDay {
                            meterRow(label: loc("7d"), window: sevenDay, now: context.date)
                        }
                        if let extra = snapshot.extra {
                            meterRow(label: loc("Extra"), window: extra, now: context.date)
                        }
                    }
                }
                if snapshot.status == .rateLimited {
                    Text(loc("Usage paused — retrying shortly"))
                        .font(.system(size: 9))
                        .foregroundStyle(IslandStyle.tertiaryText)
                }
            } else {
                Text(statusCopy(snapshot))
                    .font(.system(size: 10))
                    .foregroundStyle(IslandStyle.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private func meterRow(label: String, window: AgentUsageWindow, now: Date) -> some View {
        let remaining = Int(window.remainingPercent.rounded())
        let resetPhrase = window.resetsAt.map { AgentUsageResetCopy.phrase(until: $0, now: now) }
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(IslandStyle.secondaryText)
                    .fixedSize()

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.08))
                        Capsule(style: .continuous)
                            .fill(barColor(window.tightness))
                            .frame(width: max(3, geo.size.width * CGFloat(window.remainingPercent / 100)))
                    }
                }
                .frame(height: 5)

                Text(locFormat("%lld%% left", remaining))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(labelColor(window.tightness))
                    .fixedSize()
            }

            if let resetPhrase {
                Text(resetPhrase)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(IslandStyle.tertiaryText)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(meterAccessibilityLabel(label: label, remaining: remaining, resetPhrase: resetPhrase))
    }

    private func meterAccessibilityLabel(label: String, remaining: Int, resetPhrase: String?) -> String {
        let quota = locFormat("%@ %lld percent left", label, remaining)
        guard let resetPhrase else { return quota }
        return quota + ". " + resetPhrase
    }

    private func statusCopy(_ snapshot: AgentUsageSnapshot) -> String {
        switch snapshot.status {
        case .signedOut:
            snapshot.agent == .claude
                ? loc("Sign in with Claude Code to see limits")
                : loc("Sign in with Codex to see limits")
        case .needsKeychainAccess:
            loc("Allow Keychain access for Claude, then tap refresh")
        case .loginExpired:
            loc("Open Claude to refresh the login")
        case .rateLimited:
            loc("Usage paused — retrying shortly")
        case .unavailable, .ready:
            loc("Limits unavailable")
        }
    }

    private func barColor(_ tightness: AgentUsageTightness) -> Color {
        switch tightness {
        case .normal: Color.white.opacity(0.55)
        case .warning: Color.orange.opacity(0.9)
        case .critical: Color.red.opacity(0.9)
        }
    }

    private func labelColor(_ tightness: AgentUsageTightness) -> Color {
        switch tightness {
        case .normal: IslandStyle.secondaryText
        case .warning: Color.orange.opacity(0.95)
        case .critical: Color.red.opacity(0.95)
        }
    }
}
