import AppKit
import Foundation

enum MenuBarIcon {
    private static let maxPointHeight: CGFloat = 12
    private static let maxPointWidth: CGFloat = 18

    static func makeTemplateImage() -> NSImage {
        guard let url = ResourceBundle.bundle.url(forResource: "MenuBarIcon", withExtension: "png"),
              let data = try? Data(contentsOf: url),
              let sourceRep = NSBitmapImageRep(data: data) else {
            return fallbackImage()
        }

        let sourceWidth = CGFloat(sourceRep.pixelsWide)
        let sourceHeight = CGFloat(sourceRep.pixelsHigh)
        guard sourceWidth > 0, sourceHeight > 0 else { return fallbackImage() }

        let aspect = sourceWidth / sourceHeight
        var pointHeight = maxPointHeight
        var pointWidth = pointHeight * aspect

        if pointWidth > maxPointWidth {
            pointWidth = maxPointWidth
            pointHeight = pointWidth / aspect
        }

        let pixelScale: CGFloat = 2
        let pixelHeight = max(1, Int((pointHeight * pixelScale).rounded()))
        let pixelWidth = max(1, Int((pointWidth * pixelScale).rounded()))

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return fallbackImage()
        }

        rep.size = NSSize(width: pointWidth, height: pointHeight)

        guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
            return fallbackImage()
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }

        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: pointWidth, height: pointHeight).fill()

        let sourceImage = NSImage(size: NSSize(width: sourceWidth, height: sourceHeight))
        sourceImage.addRepresentation(sourceRep)
        sourceImage.draw(
            in: NSRect(x: 0, y: 0, width: pointWidth, height: pointHeight),
            from: NSRect(x: 0, y: 0, width: sourceWidth, height: sourceHeight),
            operation: .sourceOver,
            fraction: 1
        )

        forceTemplateSilhouette(on: rep)

        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        image.isTemplate = true
        return image
    }

    private static func forceTemplateSilhouette(on rep: NSBitmapImageRep) {
        guard let pixels = rep.bitmapData else { return }

        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        let bytesPerPixel = rep.bitsPerPixel / rep.samplesPerPixel
        let alphaOffset = bytesPerPixel - 1

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * rep.bytesPerRow + x * bytesPerPixel
                let alpha = pixels[offset + alphaOffset]
                if alpha == 0 { continue }

                pixels[offset] = 0
                pixels[offset + 1] = 0
                pixels[offset + 2] = 0
                pixels[offset + alphaOffset] = alpha
            }
        }
    }

    private static func fallbackImage() -> NSImage {
        let image = NSImage(systemSymbolName: "waveform.path", accessibilityDescription: "NotchFlow")
        image?.isTemplate = true
        return image ?? NSImage()
    }
}
