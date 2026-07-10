import Foundation

@MainActor
enum AppController {
    static weak var appState: AppState?
    static weak var appDelegate: AppDelegate?
    static weak var panelController: NotchPanelController?
}
