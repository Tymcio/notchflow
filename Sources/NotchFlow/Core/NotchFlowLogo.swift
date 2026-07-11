import AppKit
import SwiftUI

enum NotchFlowLogo {
    static var markImage: NSImage? {
        guard let url = Bundle.module.url(forResource: "LogoMark", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = false
        return image
    }
}

struct NotchFlowLogoMark: View {
    var height: CGFloat = 34

    private var aspectRatio: CGFloat { 1024 / 509 }

    var body: some View {
        Group {
            if let image = NotchFlowLogo.markImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(aspectRatio, contentMode: .fit)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: height * 0.55, weight: .semibold))
                    .foregroundStyle(NotchFlowBrand.electricBlue)
            }
        }
        .frame(height: height)
        .accessibilityLabel("NotchFlow")
    }
}

struct SettingsBrandingHeader: View {
    var body: some View {
        VStack(spacing: 10) {
            NotchFlowLogoMark(height: 42)

            HStack(spacing: 0) {
                Text("notch")
                    .foregroundStyle(.primary)
                Text("flow")
                    .foregroundStyle(
                        LinearGradient(
                            colors: [NotchFlowBrand.aurora, NotchFlowBrand.electricBlue, NotchFlowBrand.auroraPurple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            .font(.system(size: 15, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
    }
}
