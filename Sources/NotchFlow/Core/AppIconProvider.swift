import AppKit
import SwiftUI

enum AppIconProvider {
    static func image(for bundleID: String) -> NSImage? {
        for candidate in NotificationAppCatalog.bundleIDCandidates(for: bundleID) {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: candidate) else {
                continue
            }
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return nil
    }

    static func openApplication(bundleID: String) {
        for candidate in NotificationAppCatalog.bundleIDCandidates(for: bundleID) {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: candidate) else {
                continue
            }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return
        }
    }
}

struct CatalogAppIcon: View {
    let bundleID: String
    var size: CGFloat = 18

    var body: some View {
        let safeBundleID = NotificationAppCatalog.sanitizedIconBundleID(bundleID)

        // Prefer the real macOS app icon (Signal, WhatsApp, …) over brand SF-symbol badges.
        if NotificationAppCatalog.isRecognizedNotificationIcon(safeBundleID),
           let image = AppIconProvider.image(for: safeBundleID) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        } else if let badge = NotificationAppCatalog.brandBadge(for: safeBundleID) {
            BrandBadgeIcon(badge: badge, size: size)
        } else {
            BrandBadgeIcon(
                badge: NotificationAppCatalog.genericNotificationBadge,
                size: size
            )
        }
    }
}

private struct BrandBadgeIcon: View {
    let badge: NotificationAppCatalog.BrandBadge
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: badge.gradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: badge.symbol)
                .font(.system(size: size * 0.55, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}
