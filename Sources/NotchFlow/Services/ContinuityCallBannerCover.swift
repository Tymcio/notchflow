import AppKit
import CoreGraphics
import Foundation

/// Covers the Continuity photo call card with a panel showing what's behind it.
@MainActor
enum ContinuityCallBannerCover {
    private static var panel: NSPanel?
    private static var pollTask: Task<Void, Never>?
    private static var coveredRect: CGRect?

    static func startCovering() {
        pollTask?.cancel()
        coveredRect = nil
        pollTask = Task { @MainActor in
            // The card can appear a few seconds into the ring. After the first hit
            // the card no longer moves, so tracking is just a cheap window-metadata
            // liveness check inside findCard — no further captures.
            let deadline = Date().addingTimeInterval(25)
            var covered = false
            while !Task.isCancelled, Date() < deadline {
                let hit = await coverMatchingCard()
                if covered, !hit {
                    // Card vanished — drop the cover so we don't blank the desktop.
                    panel?.orderOut(nil)
                    coveredRect = nil
                    return
                }
                covered = covered || hit
                try? await Task.sleep(for: .milliseconds(covered ? 700 : 250))
            }
        }
    }

    static func stopCovering() {
        pollTask?.cancel()
        pollTask = nil
        panel?.orderOut(nil)
        panel = nil
        coveredRect = nil
    }

    @discardableResult
    private static func coverMatchingCard() async -> Bool {
        guard let card = await ContinuityCallActions.findCard() else { return false }
        if card.cgRect == coveredRect, panel?.isVisible == true {
            return true
        }
        guard let screen = NSScreen.screens.first(where: {
            let midY = $0.frame.maxY - (card.cgRect.midY)
            return $0.frame.contains(NSPoint(x: card.cgRect.midX, y: midY))
        }) ?? NSScreen.main else { return false }

        let appKitY = screen.frame.maxY - card.cgRect.minY - card.cgRect.height
        let frame = NSRect(
            x: card.cgRect.minX,
            y: appKitY,
            width: card.cgRect.width,
            height: card.cgRect.height
        )

        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setFrame(frame, display: true)

        if let behind = await ContinuityCallActions.imageBehindCard(card) {
            let imageView = NSImageView(image: NSImage(cgImage: behind, size: frame.size))
            imageView.imageScaling = .scaleAxesIndependently
            imageView.frame = NSRect(origin: .zero, size: frame.size)
            panel.contentView = imageView
        } else {
            panel.backgroundColor = .black
            panel.contentView = NSView(frame: .zero)
        }

        panel.orderFrontRegardless()
        coveredRect = card.cgRect
        return true
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = true
        panel.backgroundColor = .black
        panel.hasShadow = false
        // Click-through: synthetic Answer/Decline clicks must reach the card underneath.
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        return panel
    }
}
