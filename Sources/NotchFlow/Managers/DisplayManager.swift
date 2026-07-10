import AppKit
import Combine
import Foundation

@MainActor
final class DisplayManager: ObservableObject {
    @Published private(set) var activeScreen: NSScreen?
    @Published private(set) var geometry: NotchGeometry?
    @Published private(set) var isPointerNearNotch = false
    @Published private(set) var shouldHideIsland = false

    /// Set by NotchPanelController while the island is visible, so hover keeps it open.
    var activePanelFrame: CGRect?

    private var screenChangeObserver: NSObjectProtocol?
    private var workspaceObserver: NSObjectProtocol?
    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?
    private let settings: NotchSettings
    private let menuBarLayoutManager: MenuBarLayoutManager
    private var cancellables = Set<AnyCancellable>()
    private var mouseMoveCoalesceTask: Task<Void, Never>?

    init(settings: NotchSettings, menuBarLayoutManager: MenuBarLayoutManager) {
        self.settings = settings
        self.menuBarLayoutManager = menuBarLayoutManager
        refreshActiveScreen()
        startObservers()
        startWorkspaceObserver()
        bindMenuBarLayout()
    }

    deinit {
        mouseMoveCoalesceTask?.cancel()
        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
        }
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
        }
    }

    func refreshActiveScreen() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        activeScreen = screen
        menuBarLayoutManager.setActiveScreen(screen)
        menuBarLayoutManager.refresh(for: screen)
        recomputeGeometry(for: screen)
    }

    private func recomputeGeometry(for screen: NSScreen?) {
        if let screen {
            let menuEdge = menuBarLayoutManager.menuRightEdgeX(for: screen)
            geometry = NotchGeometry.make(
                for: screen,
                settings: settings,
                appMenuRightEdgeX: menuEdge
            )
        } else {
            geometry = nil
        }
    }

    /// Synchronously re-reads the app menu edge and rebuilds geometry.
    /// Called right before presenting the idle island so wing widths are fresh.
    func refreshMenuLayoutNow() {
        menuBarLayoutManager.refresh(for: activeScreen)
        recomputeGeometry(for: activeScreen)
    }

    private func bindMenuBarLayout() {
        menuBarLayoutManager.$appMenuRightEdgeX
            .sink { [weak self] _ in
                self?.recomputeGeometry(for: self?.activeScreen)
            }
            .store(in: &cancellables)
    }

    func updatePointerProximity(at location: NSPoint) {
        guard let geometry else {
            isPointerNearNotch = false
            return
        }

        let threshold = NotchFlowConstants.hoverExpandThreshold
        let triggerRect = geometry.hoverTriggerRect.insetBy(dx: -threshold, dy: -threshold)

        isPointerNearNotch = triggerRect.contains(location)
            || (activePanelFrame.map { $0.insetBy(dx: -8, dy: -8).contains(location) } ?? false)
    }

    func refreshHideState() {
        guard settings.isPremiumEnabled, !settings.hiddenAppBundleIDs.isEmpty else {
            shouldHideIsland = false
            return
        }
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            shouldHideIsland = false
            return
        }
        shouldHideIsland = settings.hiddenAppBundleIDs.contains(bundleID)
    }

    private func startWorkspaceObserver() {
        refreshHideState()
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshHideState()
                self?.menuBarLayoutManager.refresh(for: self?.activeScreen)
                self?.recomputeGeometry(for: self?.activeScreen)
            }
        }
    }

    private func startObservers() {
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshActiveScreen()
            }
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.scheduleMouseMove(NSEvent.mouseLocation)
            return event
        }

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.scheduleMouseMove(NSEvent.mouseLocation)
        }
    }

    private func scheduleMouseMove(_ location: NSPoint) {
        mouseMoveCoalesceTask?.cancel()
        mouseMoveCoalesceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(33))
            guard !Task.isCancelled else { return }
            handleMouseMove(location)
        }
    }

    private func handleMouseMove(_ location: NSPoint) {
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(location) }),
           screen != activeScreen {
            activeScreen = screen
            menuBarLayoutManager.setActiveScreen(screen)
            menuBarLayoutManager.refresh(for: screen)
            recomputeGeometry(for: screen)
        }
        updatePointerProximity(at: location)
    }

}
