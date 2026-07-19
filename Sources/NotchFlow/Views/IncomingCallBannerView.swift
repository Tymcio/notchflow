import AppKit
import SwiftUI

/// Incoming-call cover over the notch — same simple silhouette as notifications.
struct IncomingCallBannerView: View {
    let call: IncomingCallActivity
    let bannerWidth: CGFloat
    let bannerHeight: CGFloat
    let topInset: CGFloat
    let onAnswer: () -> Void
    let onDecline: () -> Void

    @State private var pulse = false
    @State private var appeared = false

    private var genericCaller: Bool {
        NotificationAppCatalog.isSystemCallUILabel(call.callerName)
    }

    private var displayName: String {
        genericCaller ? loc("Incoming call") : call.callerName
    }

    private var sourceLabel: String {
        let name = NotificationAppCatalog.name(for: call.appBundleID)
        if name == call.appBundleID || NotificationAppCatalog.isInternalAccessibilityLabel(name) {
            return loc("Incoming call")
        }
        return name
    }

    private var coverShape: NotchCoverBannerShape {
        NotchCoverBannerShape(bottomRadius: 24)
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: max(0, topInset - 2))

            HStack(spacing: 12) {
                avatar
                VStack(alignment: .leading, spacing: 2) {
                    if !genericCaller {
                        Text(sourceLabel)
                            .font(.system(size: IncomingCallBannerMetrics.sourceFontSize, weight: .medium, design: .rounded))
                            .foregroundStyle(IslandStyle.secondaryText)
                            .lineLimit(1)
                    }
                    Text(displayName)
                        .font(.system(size: IncomingCallBannerMetrics.callerFontSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(IslandStyle.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    callActionButton(
                        systemImage: "phone.down.fill",
                        label: loc("Decline call"),
                        tint: .red,
                        action: onDecline
                    )
                    callActionButton(
                        systemImage: "phone.fill",
                        label: loc("Answer call"),
                        tint: .green,
                        action: onAnswer
                    )
                }
            }
            .padding(.leading, IncomingCallBannerMetrics.horizontalPadding)
            .padding(.trailing, IncomingCallBannerMetrics.horizontalPadding - 2)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, minHeight: NotchFlowConstants.incomingCallDropContentHeight, alignment: .center)
        }
        .frame(width: bannerWidth, height: bannerHeight, alignment: .top)
        .background {
            coverShape.fill(IslandStyle.islandFill)
        }
        .clipShape(coverShape)
        .overlay {
            coverShape.stroke(IslandStyle.surfaceStroke, lineWidth: 0.5)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -6)
        .onAppear {
            pulse = true
            withAnimation(.easeOut(duration: 0.22)) {
                appeared = true
            }
        }
    }

    @ViewBuilder
    private var avatar: some View {
        ZStack {
            Circle()
                .fill(Color.green.opacity(0.22))
                .frame(width: pulse ? 36 : 30, height: pulse ? 36 : 30)
                .animation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true), value: pulse)

            if NotificationAppCatalog.isCatalogApp(call.appBundleID)
                || NotificationAppCatalog.isMessagingApp(call.appBundleID) {
                CatalogAppIcon(bundleID: call.appBundleID, size: IncomingCallBannerMetrics.avatarSize)
                    .clipShape(Circle())
            } else {
                monogram
            }
        }
        .frame(width: 36, height: 36)
    }

    private var monogram: some View {
        let letter = displayName.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init) ?? "📞"
        return ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            NotchFlowBrand.electricBlue.opacity(0.85),
                            NotchFlowBrand.auroraPurple.opacity(0.75),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: IncomingCallBannerMetrics.avatarSize, height: IncomingCallBannerMetrics.avatarSize)
            Text(letter.uppercased())
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private func callActionButton(
        systemImage: String,
        label: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: IncomingCallBannerMetrics.buttonSize, height: IncomingCallBannerMetrics.buttonSize)
                .background(Circle().fill(tint.opacity(0.92)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

enum IncomingCallBannerMetrics {
    static let sourceFontSize: CGFloat = 10
    static let callerFontSize: CGFloat = 14
    static let horizontalPadding: CGFloat = 14
    static let avatarSize: CGFloat = 30
    static let buttonSize: CGFloat = 30
    static let buttonSpacing: CGFloat = 6
    static let contentSpacing: CGFloat = 10

    @MainActor
    static func preferredWidth(for call: IncomingCallActivity, cutoutWidth: CGFloat) -> CGFloat {
        let genericCaller = NotificationAppCatalog.isSystemCallUILabel(call.callerName)
        let displayName = genericCaller ? loc("Incoming call") : call.callerName
        let callerWidth = width(of: displayName, font: .systemFont(ofSize: callerFontSize, weight: .semibold))
        var textWidth = callerWidth
        if !genericCaller {
            let source = NotificationAppCatalog.name(for: call.appBundleID)
            let sourceWidth = width(of: source, font: .systemFont(ofSize: sourceFontSize, weight: .medium))
            textWidth = max(textWidth, sourceWidth)
        }

        let actions = buttonSize * 2 + buttonSpacing
        let total = (
            horizontalPadding
                + 36
                + contentSpacing
                + textWidth
                + contentSpacing
                + actions
                + horizontalPadding
        ).rounded(.up)

        let minimum = max(cutoutWidth + 72, NotchFlowConstants.minIncomingCallBannerWidth)
        return min(max(minimum, total), NotchFlowConstants.maxIncomingCallBannerWidth)
    }

    private static func width(of text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }
}
