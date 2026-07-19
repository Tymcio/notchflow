import SwiftUI

@main
struct NotchFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Intentionally no SwiftUI `Settings` scene. An empty one opened a blank
        // "Settings (NotchFlow)" window when switching to `.regular`.
        // Real settings UI is hosted by `SettingsWindowController`.
        // SwiftUI still requires at least one scene — keep an inert, never-inserted extra.
        MenuBarExtra(isInserted: .constant(false)) {
            EmptyView()
        } label: {
            EmptyView()
        }
    }
}
