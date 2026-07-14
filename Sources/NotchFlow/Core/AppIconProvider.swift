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
        if let image = AppIconProvider.image(for: bundleID) {
            Image(nsImage: image)
                .resizable()
                .frame(width: size, height: size)
        } else if let badge = NotificationAppCatalog.brandBadge(for: bundleID) {
            BrandBadgeIcon(badge: badge, size: size)
        } else {
            Image(systemName: "app.fill")
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
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
