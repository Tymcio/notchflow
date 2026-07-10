import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState?
    private var panelController: NotchPanelController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let state = AppState()
        appState = state
        AppController.appState = state
        AppController.appDelegate = self

        panelController = NotchPanelController(displayManager: state.displayManager, appState: state)

        configureStatusItem()
        configureLaunchAtLogin()
        configureSparkle()

        Task {
            await state.start()
        }

        showFirstLaunchHintIfNeeded()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            urls.forEach { AppController.appState?.handleURL($0) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func openSettings() {
        guard let appState else { return }
        SettingsWindowController.shared.show(appState: appState)
    }

    func showIsland() {
        panelController?.showFromMenu()
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }

        button.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "NotchFlow")
        button.image?.isTemplate = true
        button.toolTip = "NotchFlow — najedź na notch, aby otworzyć"

        let menu = NSMenu()
        menu.addItem(withTitle: "Pokaż wyspę Notch", action: #selector(showIslandAction), keyEquivalent: "")
        menu.addItem(withTitle: "Ustawienia…", action: #selector(openSettingsAction), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Zakończ NotchFlow", action: #selector(quitAction), keyEquivalent: "q")

        for item in menu.items {
            item.target = self
        }

        statusItem?.menu = menu
    }

    @objc private func showIslandAction() {
        showIsland()
    }

    @objc private func openSettingsAction() {
        openSettings()
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }

    private func configureLaunchAtLogin() {
        if NotchSettings.shared.launchAtLogin {
            LaunchAtLoginService.enable()
        }
    }

    private func configureSparkle() {
        #if canImport(Sparkle)
        SparkleUpdaterController.shared.start()
        #endif
    }

    private func showFirstLaunchHintIfNeeded() {
        let key = "hasSeenMenuBarHint"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        NotificationService.post(
            title: "NotchFlow działa",
            body: "Najedź na środek górnej krawędzi ekranu (obszar notcha), aby otworzyć NotchFlow."
        )
    }
}
