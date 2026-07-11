import AppKit
import ApplicationServices
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class DisplayManager: ObservableObject {
    @Published private(set) var activeScreen: NSScreen?
    @Published private(set) var geometry: NotchGeometry?
    @Published private(set) var isPointerNearNotch = false
    @Published private(set) var isDragNearNotch = false
    @Published private(set) var shouldHideIsland = false

    /// Set by NotchPanelController while the island is visible, so hover keeps it open.
    var activePanelFrame: CGRect?

    var isNotchInteractionActive: Bool {
        isPointerNearNotch || isDragNearNotch
    }

    private var screenChangeObserver: NSObjectProtocol?
    private var workspaceObserver: NSObjectProtocol?
    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var dragMonitor: Any?
    private var localDragMonitor: Any?
    private var dragEndMonitor: Any?
    private var localDragEndMonitor: Any?
    private let settings: NotchSettings
    private let menuBarLayoutManager: MenuBarLayoutManager
    private var cancellables = Set<AnyCancellable>()
    private var mouseMoveCoalesceTask: Task<Void, Never>?
    private var proximityPollTask: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?

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
        if let localDragMonitor {
            NSEvent.removeMonitor(localDragMonitor)
        }
        if let dragMonitor {
            NSEvent.removeMonitor(dragMonitor)
        }
        if let localDragEndMonitor {
            NSEvent.removeMonitor(localDragEndMonitor)
        }
        if let dragEndMonitor {
            NSEvent.removeMonitor(dragEndMonitor)
        }
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
        proximityPollTask?.cancel()
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

        let triggerRect: CGRect
        if geometry.hasPhysicalNotch {
            // Widen horizontally; allow a few points vertically for menu-bar coordinate rounding.
            triggerRect = geometry.hoverTriggerRect.insetBy(
                dx: -NotchFlowConstants.hoverNotchHorizontalExpand,
                dy: -NotchFlowConstants.hoverNotchHorizontalExpand
            )
        } else {
            triggerRect = geometry.hoverTriggerRect.insetBy(
                dx: -NotchFlowConstants.hoverExpandThreshold,
                dy: -NotchFlowConstants.hoverExpandThreshold
            )
        }

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

        installMouseMonitors()

        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshMouseMonitoringIfNeeded()
            }
        }

        localDragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
            self?.handleDrag(at: NSEvent.mouseLocation)
            return event
        }

        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            self?.handleDrag(at: NSEvent.mouseLocation)
        }

        localDragEndMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            self?.endDragSession()
            return event
        }

        dragEndMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            self?.endDragSession()
        }
    }

    private func handleDrag(at location: NSPoint) {
        guard isFileDragActive() else {
            if isDragNearNotch {
                endDragSession()
            }
            return
        }

        if let screen = NSScreen.screens.first(where: { $0.frame.contains(location) }),
           screen != activeScreen {
            activeScreen = screen
            menuBarLayoutManager.setActiveScreen(screen)
            menuBarLayoutManager.refresh(for: screen)
            recomputeGeometry(for: screen)
        }

        let nearDropZone = isLocationInDragDropZone(location)
        isDragNearNotch = nearDropZone
        if nearDropZone {
            isPointerNearNotch = true
        } else {
            updatePointerProximity(at: location)
        }
    }

    private func endDragSession() {
        guard isDragNearNotch else { return }
        isDragNearNotch = false
        updatePointerProximity(at: NSEvent.mouseLocation)
    }

    private func isFileDragActive() -> Bool {
        let pasteboard = NSPasteboard(name: .drag)
        guard let types = pasteboard.types, !types.isEmpty else { return false }

        let fileTypeStrings: Set<String> = [
            NSPasteboard.PasteboardType.fileURL.rawValue,
            NSPasteboard.PasteboardType.URL.rawValue,
            UTType.fileURL.identifier,
            UTType.item.identifier,
            UTType.content.identifier,
            "NSFilenamesPboardType",
            "public.file-url",
            "public.url"
        ]

        return types.contains { fileTypeStrings.contains($0.rawValue) }
    }

    private func isLocationInDragDropZone(_ location: NSPoint) -> Bool {
        guard let geometry else { return false }

        let width = geometry.expandedSize.width + NotchFlowConstants.dragDropZoneHorizontalPadding * 2
        let height = geometry.notchTopInset + geometry.expandedSize.height + NotchFlowConstants.dragDropZoneVerticalPadding

        let dropZone: CGRect
        if geometry.hasPhysicalNotch, let notchLeftX = geometry.notchLeftX {
            dropZone = CGRect(
                x: notchLeftX + geometry.physicalNotchCutoutWidth / 2 - width / 2,
                y: geometry.screenTopY - height,
                width: width,
                height: height
            )
        } else {
            dropZone = CGRect(
                x: geometry.screenMidX - width / 2,
                y: geometry.screenTopY - height,
                width: width,
                height: height
            )
        }

        return dropZone.contains(location)
    }

    private func installMouseMonitors() {
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.scheduleMouseMove(NSEvent.mouseLocation)
            return event
        }

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.scheduleMouseMove(NSEvent.mouseLocation)
        }

        if mouseMonitor == nil {
            NotchFlowLog.hover.warning(
                "Global mouse monitor unavailable — using menu-bar polling fallback (grant Accessibility for best results)"
            )
            startProximityPolling()
        } else {
            stopProximityPolling()
        }
    }

    private func refreshMouseMonitoringIfNeeded() {
        guard mouseMonitor == nil, AXIsProcessTrusted() else { return }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.scheduleMouseMove(NSEvent.mouseLocation)
        }
        if mouseMonitor != nil {
            NotchFlowLog.hover.debug("Global mouse monitor restored after Accessibility grant")
            stopProximityPolling()
        }
    }

    private func startProximityPolling() {
        guard proximityPollTask == nil else { return }
        proximityPollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let location = NSEvent.mouseLocation
                let interval: Duration = isNearAnyMenuBar(location)
                    ? .milliseconds(33)
                    : .milliseconds(250)
                if isNearAnyMenuBar(location) {
                    handleMouseMove(location)
                }
                try? await Task.sleep(for: interval)
            }
        }
    }

    private func stopProximityPolling() {
        proximityPollTask?.cancel()
        proximityPollTask = nil
    }

    private func isNearAnyMenuBar(_ location: NSPoint) -> Bool {
        for screen in NSScreen.screens {
            let top = screen.frame.maxY
            let band = max(screen.safeAreaInsets.top, NotchFlowConstants.virtualCapsuleHeight)
            if location.y >= top - band - NotchFlowConstants.hoverExpandThreshold,
               location.y <= top + 4 {
                return true
            }
        }
        return false
    }

    private func scheduleMouseMove(_ location: NSPoint) {
        if shouldUpdateProximityImmediately(at: location) {
            mouseMoveCoalesceTask?.cancel()
            handleMouseMove(location)
            return
        }

        mouseMoveCoalesceTask?.cancel()
        mouseMoveCoalesceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled else { return }
            handleMouseMove(location)
        }
    }

    private func shouldUpdateProximityImmediately(at location: NSPoint) -> Bool {
        guard let geometry else { return false }
        // Fast-path only inside the menu-bar band, not the web content below.
        return location.y <= geometry.screenTopY
            && location.y >= geometry.screenTopY - geometry.notchTopInset
    }

    private func handleMouseMove(_ location: NSPoint) {
        if isDragNearNotch {
            return
        }

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
