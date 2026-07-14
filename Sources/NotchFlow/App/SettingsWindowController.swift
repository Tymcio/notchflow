import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show(appState: AppState, tab: SettingsTab = .general) {
        NSApp.setActivationPolicy(.regular)

        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(appState: appState, initialTab: tab))

            let newWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            newWindow.title = "Ustawienia NotchFlow"
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
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closedWindow = notification.object as? NSWindow, closedWindow === window else { return }
        NSApp.setActivationPolicy(.accessory)
    }
}
