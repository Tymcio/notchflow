import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let statusAutosaveName = "eu.notchflow.app.status"

    private var appState: AppState?
    private var panelController: NotchPanelController?
    private var statusItem: NSStatusItem?
    private var statusItemVisibilityObservation: NSKeyValueObservation?
    private var workspaceActivationObserver: NSObjectProtocol?
    private var statusItemRestoreTask: Task<Void, Never>?

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

    func applicationDidBecomeActive(_ notification: Notification) {
        ensureStatusItemVisible()
    }

    func openSettings() {
        guard let appState else { return }
        SettingsWindowController.shared.show(appState: appState)
    }

    func showIsland() {
        panelController?.showFromMenu()
    }

    func hideIsland() {
        panelController?.hideFromUser()
    }

    private func configureStatusItem() {
        clearPersistedStatusItemVisibility()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        // Stable identity + no removalAllowed: macOS otherwise treats the icon as optional
        // and can hide it together with other menu bar items in System Settings.
        item.behavior = []
        forceStatusItemVisible(item)

        statusItemVisibilityObservation = item.observe(\.isVisible, options: [.new]) { [weak self] item, change in
            guard change.newValue == false else { return }
            DispatchQueue.main.async { [weak self] in
                self?.restoreStatusItemVisibility(item)
            }
        }

        workspaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.scheduleStatusItemVisibilityRestore()
            }
        }

        guard let button = item.button else { return }

        button.image = MenuBarIcon.makeTemplateImage()
        button.toolTip = "NotchFlow — najedź na notch, aby otworzyć"

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "Pokaż wyspę Notch", action: #selector(toggleIslandAction), keyEquivalent: "")
        menu.addItem(withTitle: "Ustawienia…", action: #selector(openSettingsAction), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Zakończ NotchFlow", action: #selector(quitAction), keyEquivalent: "q")

        for menuEntry in menu.items {
            menuEntry.target = self
        }

        item.menu = menu
    }

    private func clearPersistedStatusItemVisibility() {
        UserDefaults.standard.removeObject(forKey: Self.persistedVisibilityKey)
    }

    private func forceStatusItemVisible(_ item: NSStatusItem) {
        item.isVisible = true
        item.autosaveName = Self.statusAutosaveName
        item.isVisible = true
        DispatchQueue.main.async {
            item.isVisible = true
        }
    }

    private func restoreStatusItemVisibility(_ item: NSStatusItem) {
        clearPersistedStatusItemVisibility()
        item.isVisible = true
        DispatchQueue.main.async {
            item.isVisible = true
        }
    }

    private func ensureStatusItemVisible() {
        guard let statusItem else { return }
        guard !statusItem.isVisible else { return }
        restoreStatusItemVisibility(statusItem)
    }

    private func scheduleStatusItemVisibilityRestore() {
        ensureStatusItemVisible()

        statusItemRestoreTask?.cancel()
        statusItemRestoreTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.ensureStatusItemVisible()
            }
        }
    }

    private static var persistedVisibilityKey: String {
        "NSStatusItem Visibility \(statusAutosaveName)"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let visible = panelController?.isIslandVisible == true
        menu.item(at: 0)?.title = visible ? "Ukryj wyspę Notch" : "Pokaż wyspę Notch"
    }

    @objc private func toggleIslandAction() {
        if panelController?.isIslandVisible == true {
            hideIsland()
        } else {
            showIsland()
        }
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
