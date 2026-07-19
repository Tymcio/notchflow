import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show(appState: AppState, tab: SettingsTab = .general) {
        NSApp.setActivationPolicy(.regular)
        dismissSwiftUISettingsWindows()

        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(appState: appState, initialTab: tab))

            let newWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            newWindow.title = loc("NotchFlow Settings")
            newWindow.contentViewController = hosting
            newWindow.minSize = NSSize(width: 640, height: 480)
            newWindow.isReleasedWhenClosed = false
            newWindow.delegate = self
            // Open settings on the currently active Space (even if the user is in full-screen).
            newWindow.collectionBehavior.insert(.moveToActiveSpace)
            newWindow.collectionBehavior.insert(.fullScreenAuxiliary)
            newWindow.center()
            window = newWindow
        } else if let hosting = window?.contentViewController as? NSHostingController<SettingsView> {
            hosting.rootView = SettingsView(appState: appState, initialTab: tab)
        }

        window?.collectionBehavior.insert(.moveToActiveSpace)
        window?.collectionBehavior.insert(.fullScreenAuxiliary)
        if window?.isMiniaturized == true {
            window?.deminiaturize(nil)
        }
        window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        // Right after switching from .accessory to .regular, activation in the same runloop
        // pass is often ignored (Sonoma cooperative activation) — retry on the next turn.
        DispatchQueue.main.async { [weak self] in
            self?.dismissSwiftUISettingsWindows()
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            self?.window?.makeKeyAndOrderFront(nil)
            self?.window?.orderFrontRegardless()
        }
    }

    /// Closes the system SwiftUI Settings scene window ("Settings (AppName)"), if any.
    private func dismissSwiftUISettingsWindows() {
        for candidate in NSApp.windows {
            if candidate === window { continue }
            let title = candidate.title
            // Localized SwiftUI Settings titles look like "Settings (NotchFlow)" / "Ustawienia (NotchFlow)".
            guard title.contains("NotchFlow"), title.contains("("), title.contains(")") else { continue }
            candidate.close()
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let closedWindow = notification.object as? NSWindow, closedWindow === window else { return }
        NSApp.setActivationPolicy(.accessory)
    }
}
