import AppKit
import SwiftUI

/// Large notification cover over the notch — icon + app name, no message body.
struct NotificationBannerView: View {
    let notification: NotificationPeekActivity
    let bannerWidth: CGFloat
    let bannerHeight: CGFloat
    /// Menu-bar / cutout band kept clear of content (camera housing).
    let topInset: CGFloat
    let onOpen: () -> Void

    @State private var appeared = false

    private var statusLabel: String {
        NotificationAppCatalog.isMessagingApp(notification.appBundleID)
            ? loc("New message")
            : loc("Notification")
    }

    private var coverShape: NotchCoverBannerShape {
        NotchCoverBannerShape(bottomRadius: 24)
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: max(0, topInset - 2))

                HStack(spacing: 12) {
                    CatalogAppIcon(
                        bundleID: notification.appBundleID,
                        size: NotificationBannerMetrics.avatarSize
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(notification.appName)
                            .font(.system(size: NotificationBannerMetrics.appFontSize, weight: .semibold, design: .rounded))
                            .foregroundStyle(IslandStyle.primaryText)
                            .lineLimit(1)
                        Text(statusLabel)
                            .font(.system(size: NotificationBannerMetrics.statusFontSize, weight: .medium, design: .rounded))
                            .foregroundStyle(IslandStyle.secondaryText)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, NotificationBannerMetrics.horizontalPadding)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, minHeight: NotchFlowConstants.dropBannerContentHeight, alignment: .center)
            }
            .frame(width: bannerWidth, height: bannerHeight, alignment: .top)
            .contentShape(coverShape)
        }
        .buttonStyle(.plain)
        .background {
            coverShape.fill(IslandStyle.islandFill)
        }
        .clipShape(coverShape)
        .overlay {
            coverShape.stroke(IslandStyle.surfaceStroke, lineWidth: 0.5)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -6)
        .accessibilityLabel("\(notification.appName), \(statusLabel)")
        .accessibilityHint(loc("Open app"))
        .onAppear {
            withAnimation(.easeOut(duration: 0.22)) {
                appeared = true
            }
        }
    }
}

enum NotificationBannerMetrics {
    static let appFontSize: CGFloat = 14
    static let statusFontSize: CGFloat = 11
    static let horizontalPadding: CGFloat = 16
    static let avatarSize: CGFloat = 32

    @MainActor
    static func preferredWidth(for notification: NotificationPeekActivity, cutoutWidth: CGFloat) -> CGFloat {
        let status = NotificationAppCatalog.isMessagingApp(notification.appBundleID)
            ? loc("New message")
            : loc("Notification")
        let appWidth = width(of: notification.appName, font: .systemFont(ofSize: appFontSize, weight: .semibold))
        let statusWidth = width(of: status, font: .systemFont(ofSize: statusFontSize, weight: .medium))
        let textWidth = max(appWidth, statusWidth)

        let total = (horizontalPadding + avatarSize + 12 + textWidth + horizontalPadding).rounded(.up)
        let minimum = max(cutoutWidth + 72, NotchFlowConstants.minNotificationBannerWidth)
        return min(max(minimum, total), NotchFlowConstants.maxNotificationBannerWidth)
    }

    private static func width(of text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }
}
