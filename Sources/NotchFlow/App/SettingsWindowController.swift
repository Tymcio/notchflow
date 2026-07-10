import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show(appState: AppState) {
        NSApp.setActivationPolicy(.regular)

        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(appState: appState))

            let newWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            newWindow.title = "Ustawienia NotchFlow"
            newWindow.contentViewController = hosting
            newWindow.isReleasedWhenClosed = false
            newWindow.delegate = self
            newWindow.center()
            window = newWindow
        } else if let hosting = window?.contentViewController as? NSHostingController<SettingsView> {
            hosting.rootView = SettingsView(appState: appState)
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closedWindow = notification.object as? NSWindow, closedWindow === window else { return }
        NSApp.setActivationPolicy(.accessory)
    }
}
