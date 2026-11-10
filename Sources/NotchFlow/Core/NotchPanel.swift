import AppKit
import Combine
import QuartzCore
import SwiftUI

@MainActor
final class NotchPanel: NSPanel {
    private let hostingView: NotchHostingView<NotchIslandView>

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(rootView: NotchIslandView) {
        hostingView = NotchHostingView(rootView: rootView)
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        configurePanel()
        contentView = hostingView
        // Content view must track the window during animated resizes,
        // otherwise the SwiftUI content stays at the old size and gets clipped.
        hostingView.autoresizingMask = [.width, .height]
        // Never let SwiftUI content drive the window size: AppKit resizes such windows
        // keeping the bottom edge fixed, which pushes the panel upward past the screen top.
        // The window frame is owned exclusively by NotchGeometry via setFrame(_:animated:).
        hostingView.sizingOptions = []
    }

    func updateRootView(_ rootView: NotchIslandView) {
        hostingView.rootView = rootView
    }

    func activateForInput() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    // Window frame changes are always applied instantly. Animating via
    // `animator().setFrame` is unsafe here: geometry can retarget the frame several
    // times in quick succession (module switch + intrinsic height measurement), and
    // retargeting an in-flight NSWindow frame animation throws the window to wild
    // positions (observed x of -1039 and +11537) before it settles back.
    func setFrame(_ frame: CGRect, animated: Bool) {
        super.setFrame(frame, display: true)
    }

    func setIgnoresMouseEvents(_ ignore: Bool) {
        ignoresMouseEvents = ignore
    }

    private func configurePanel() {
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isMovableByWindowBackground = false
        acceptsMouseMovedEvents = true
    }
}

/// Allows clicks on controls without an extra activation click in `.nonactivatingPanel`.
private final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override var safeAreaInsets: NSEdgeInsets { .init() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        super.mouseDown(with: event)
    }
}

@MainActor
final class NotchPanelController: ObservableObject {
    @Published private(set) var isExpanded = false
    @Published private(set) var isVisible = false

    private var panel: NotchPanel?
    private var hideTask: Task<Void, Never>?
    private var hoverDwellTask: Task<Void, Never>?
    private var hoverExitGraceTask: Task<Void, Never>?
    // nonisolated(unsafe): only touched on the main actor; the nonisolated deinit reads them
    // once after the last reference is gone.
    nonisolated(unsafe) private var clickMonitor: Any?
    nonisolated(unsafe) private var escapeMonitor: Any?
    nonisolated(unsafe) private var spaceChangeObserver: NSObjectProtocol?
    /// Last known answer to "may idle wings show on the active display?", to react only to changes.
    private var lastIdleAllowedByGeometry = true
    private var lastShowedBareCapsule = false

    /// Something should sit in the idle island: a live activity, or the bare menu-bar capsule
    /// on a notch-less display set to "Top center".
    private var wantsIdle: Bool {
        appState.shouldShowIdleNotch || displayManager.geometry?.showsCapsuleWhileIdle == true
    }
    private var suppressAutoShow = false
    private var suppressQuickExpandUntilHoverEnd = false
    private let displayManager: DisplayManager
    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()

    init(displayManager: DisplayManager, appState: AppState) {
        self.displayManager = displayManager
        self.appState = appState
        AppController.panelController = self
        appState.onLiveActivityChange = { [weak self] in
            self?.handleLiveActivityChange()
        }
        appState.onShelfChange = { [weak self] in
            self?.refreshViewIfVisible()
        }
        bind()
        installClickMonitor()
        installSpaceChangeObserver()
    }

    deinit {
        if let spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceChangeObserver)
        }
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
        }
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
    }

    func prepareForTyping() {
        ensurePanel()
        panel?.activateForInput()
    }

    func showFromMenu() {
        suppressAutoShow = false
        presentExpanded()
    }

    func hideFromUser() {
        suppressAutoShow = true
        dismissImmediately()
    }

    var isIslandVisible: Bool {
        isVisible
    }

    private func bind() {
        Publishers.CombineLatest(
            displayManager.$isPointerNearNotch,
            displayManager.$isDragNearNotch
        )
        .map { $0 || $1 }
        .removeDuplicates()
        .sink { [weak self] isNear in
            self?.updateVisibility(hovering: isNear)
        }
        .store(in: &cancellables)

        displayManager.$geometry
            .removeDuplicates()
            .sink { [weak self] geometry in
                guard let self else { return }
                // @Published delivers before the property is stored: place the panel with the
                // new value (reading `displayManager.geometry` here would get the old display),
                // then finish visibility once the property is set.
                self.repositionIfVisible(animated: self.isExpanded, geometry: geometry)
                DispatchQueue.main.async { [weak self] in
                    self?.reconcileIdleVisibility()
                }
            }
            .store(in: &cancellables)

        displayManager.$shouldHideIsland
            .sink { [weak self] hidden in
                guard let self else { return }
                if hidden, !self.hasPriorityLiveActivity {
                    self.dismissImmediately()
                } else if !hidden {
                    self.updateVisibility(hovering: self.displayManager.isNotchInteractionActive)
                }
            }
            .store(in: &cancellables)
    }

    private func updateVisibility(hovering: Bool) {
        guard !displayManager.shouldHideIsland || hasPriorityLiveActivity else {
            dismissImmediately()
            return
        }

        if hovering {
            hoverExitGraceTask?.cancel()
            suppressAutoShow = false
            hideTask?.cancel()
            if displayManager.isFileDragInProgress && displayManager.isDragNearNotch {
                hoverDwellTask?.cancel()
                appState.activeModule = .shelf
                presentExpanded()
                return
            }
            if isExpanded {
                hoverDwellTask?.cancel()
                presentExpanded()
                return
            }
            if suppressQuickExpandUntilHoverEnd {
                keepIdleVisibleIfNeeded()
                return
            }
            // During an agent prompt the wings show Allow / Deny, so a quick click there still
            // works; resting on the island longer opens the Agents tab with the prompt on top.
            if hasAgentAttention {
                scheduleExpandAfterHoverDwell(
                    milliseconds: NotchFlowConstants.agentPromptHoverExpandDwellMilliseconds,
                    module: .agents
                )
                return
            }
            scheduleExpandAfterHoverDwell()
            return
        }

        scheduleHoverExitAfterGrace()
    }

    private func scheduleHoverExitAfterGrace() {
        hoverExitGraceTask?.cancel()
        hoverExitGraceTask = Task { @MainActor in
            try? await Task.sleep(
                for: .milliseconds(NotchFlowConstants.hoverProximityLossGraceMilliseconds)
            )
            guard !Task.isCancelled else {
                hoverExitGraceTask = nil
                return
            }
            handleHoverEnded()
            hoverExitGraceTask = nil
        }
    }

    private func handleHoverEnded() {
        hoverDwellTask?.cancel()
        suppressQuickExpandUntilHoverEnd = false

        if suppressAutoShow {
            scheduleHide()
            return
        }

        if wantsIdle, !shouldSuppressIdleForMenuOverlap {
            if displayManager.geometry != nil {
                presentIdle()
            } else {
                dismissImmediately()
            }
            return
        }

        scheduleHide()
    }

    /// On displays without a notch, idle wings can become unavailable (menus under them, the menu
    /// bar hidden, placement turned Off, pointer moved to such a display) or available again while
    /// nothing else changes; follow those transitions. Hardware-notch geometry always allows idle
    /// wings, so notched MacBooks never act here.
    private func reconcileIdleVisibility() {
        guard let flags = displayManager.geometry?.idleVisibilityFlags else { return }
        let leftBareCapsule = lastShowedBareCapsule && !flags.bareCapsule
        if flags.allowed == lastIdleAllowedByGeometry && flags.bareCapsule == lastShowedBareCapsule { return }
        lastIdleAllowedByGeometry = flags.allowed
        lastShowedBareCapsule = flags.bareCapsule
        if isExpanded { return }

        if !flags.allowed {
            dismissIdleNotAllowed(allowsAutomaticPresentation: flags.automatic)
        } else if wantsIdle {
            presentIdleIfHidden()
        } else if leftBareCapsule {
            // The pointer took the island from a "Top center" capsule to a display with nothing
            // to show (a hardware notch with no live activity): drop the empty capsule.
            dismissIdleIfUntouched()
        }
    }

    // Kept small and fed plain flags: Swift 6.4.2's SimplifyCFG pass crashed (release builds
    // only) when `reconcileIdleVisibility` held the whole geometry across these branches.
    private func presentIdleIfHidden() {
        if isVisible || suppressAutoShow || displayManager.shouldHideIsland { return }
        presentIdle()
    }

    private func dismissIdleIfUntouched() {
        if isVisible && !displayManager.isNotchInteractionActive {
            dismissImmediately()
        }
    }

    private func dismissIdleNotAllowed(allowsAutomaticPresentation: Bool) {
        guard isVisible else { return }
        // Calls and notification peeks still show over menus, but not when the user turned
        // the island off for this kind of display.
        let keepForPriority = allowsAutomaticPresentation && hasPriorityLiveActivity
        if !keepForPriority {
            dismissImmediately()
        }
    }

    private var shouldHideIdleForMenuOverlap: Bool {
        displayManager.geometry?.shouldHideIdleForMenuOverlap == true
    }

    /// Krótkie peeki powiadomień omijają chowanie wyspy przez overlap menu bara.
    private var hasPriorityLiveActivity: Bool {
        switch appState.activeLiveActivity {
        case .notification:
            return true
        case .agentSession(let session) where session.needsAttention:
            return true
        default:
            return false
        }
    }

    private var hasAgentAttention: Bool {
        if case .agentSession(let session) = appState.activeLiveActivity {
            return session.needsAttention
        }
        return false
    }

    private func showAgentsTabForPrompt() {
        hideTask?.cancel()
        if appState.activeModule != .agents {
            appState.activeModule = .agents
        }
        displayManager.updateExpandedHeight(for: .agents)
        refreshView()
    }

    private var shouldSuppressIdleForMenuOverlap: Bool {
        shouldHideIdleForMenuOverlap && !hasPriorityLiveActivity
    }

    private func handleLiveActivityChange() {
        // An agent prompt arriving while the island is open: keep it open on the Agents tab,
        // where the prompt sits on top, instead of folding the island away under the pointer.
        if isExpanded, hasAgentAttention {
            showAgentsTabForPrompt()
            return
        }
        // Połączenie / powiadomienie — zawsze pokaż idle, nawet gdy wyspa była rozwinięta
        // albo minutnik zajmuje skrzydła.
        if hasPriorityLiveActivity {
            suppressAutoShow = false
            hideTask?.cancel()
            if displayManager.geometry != nil {
                presentIdle()
                refreshView()
            }
            return
        }

        if isExpanded {
            return
        }

        guard !displayManager.shouldHideIsland else {
            dismissImmediately()
            return
        }

        if displayManager.isNotchInteractionActive {
            return
        }

        if suppressAutoShow {
            if isVisible {
                dismissImmediately()
            }
            return
        }

        if wantsIdle, !shouldSuppressIdleForMenuOverlap {
            if !isVisible || isExpanded {
                if displayManager.geometry != nil {
                    presentIdle()
                } else {
                    dismissImmediately()
                }
            } else {
                // Already idle-visible: the wing width may differ per activity (notification peek).
                repositionIfVisible(animated: false)
            }
        } else if isVisible {
            dismissImmediately()
        }
    }

    private func shouldKeepVisible() -> Bool {
        if wantsIdle { return true }
        if displayManager.isNotchInteractionActive { return true }
        if appState.isIslandInputFocused { return true }
        if let panel, panel.isVisible, panel.frame.insetBy(dx: -8, dy: -8).contains(NSEvent.mouseLocation) {
            return true
        }
        return false
    }

    private func presentExpanded() {
        ensurePanel()
        displayManager.updateExpandedHeight(for: appState.activeModule)
        let needsRefresh = !isVisible || !isExpanded
        isExpanded = true
        isVisible = true
        syncMediaPolling()
        if needsRefresh {
            refreshView()
        }
        repositionIfVisible(animated: false)
        panel?.setIgnoresMouseEvents(false)
        bringPanelToFront()
        installEscapeMonitorIfNeeded()
    }

    private func presentIdle() {
        guard displayManager.geometry != nil else {
            dismissImmediately()
            return
        }
        displayManager.refreshMenuLayoutNow()
        // Placement "Off" on a display without a notch: nothing idle, menu bar icon only.
        guard displayManager.geometry?.allowsAutomaticPresentation != false else {
            if isVisible, !isExpanded {
                dismissImmediately()
            }
            return
        }
        guard !shouldSuppressIdleForMenuOverlap else {
            if isVisible, !isExpanded {
                dismissImmediately()
            }
            return
        }
        ensurePanel()
        let needsRefresh = !isVisible || isExpanded
        isExpanded = false
        isVisible = true
        syncMediaPolling()
        if needsRefresh {
            refreshView()
        }
        repositionIfVisible(animated: false)
        panel?.setIgnoresMouseEvents(!idleAcceptsMouseEvents)
        bringPanelToFront()
        installEscapeMonitorIfNeeded()
    }

    private func bringPanelToFront() {
        guard let panel else { return }
        panel.orderFrontRegardless()
    }

    private func installSpaceChangeObserver() {
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isVisible else { return }
                self.displayManager.refreshGeometryNow()
                self.repositionIfVisible(animated: false)
                self.bringPanelToFront()
            }
        }
    }

    private var idleAcceptsMouseEvents: Bool {
        switch appState.activeLiveActivity {
        case .notification:
            return true
        case .agentSession(let session) where session.needsAttention:
            return true
        case .timer(let timer):
            return timer.isFinished
        default:
            return false
        }
    }

    private func installEscapeMonitorIfNeeded() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            Task { @MainActor in
                self?.hideFromUser()
            }
            return nil
        }
    }

    private func removeEscapeMonitor() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
    }

    private func ensurePanel() {
        if panel == nil {
            panel = NotchPanel(rootView: makeIslandView())
            if let geometry = displayManager.geometry {
                let frame = geometry.frame(
                    isExpanded: isExpanded,
                    isIdle: !isExpanded,
                    idleLeftWingWidth: appState.idleLeftWingWidthOverride,
                    idleRightWingWidth: appState.idleRightWingWidthOverride,
                    idleBannerWidth: appState.idleDropBannerWidth
                )
                panel?.setFrame(frame, animated: false)
            }
        }
    }

    private func keepIdleVisibleIfNeeded() {
        guard wantsIdle, !shouldSuppressIdleForMenuOverlap else { return }
        if !isVisible || isExpanded {
            presentIdle()
        }
    }

    private func scheduleExpandAfterHoverDwell(
        milliseconds: Int = NotchFlowConstants.hoverExpandDwellMilliseconds,
        module: IslandModule? = nil
    ) {
        hoverDwellTask?.cancel()
        keepIdleVisibleIfNeeded()
        hoverDwellTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(milliseconds))
            guard !Task.isCancelled else {
                hoverDwellTask = nil
                return
            }
            guard displayManager.isNotchInteractionActive else {
                hoverDwellTask = nil
                return
            }
            guard !suppressQuickExpandUntilHoverEnd else {
                hoverDwellTask = nil
                return
            }
            if displayManager.isFileDragInProgress && displayManager.isDragNearNotch {
                appState.activeModule = .shelf
            } else if let module {
                appState.activeModule = module
            }
            presentExpanded()
            hoverDwellTask = nil
        }
    }

    private func installClickMonitor() {
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.handleMouseDown(at: NSEvent.mouseLocation)
            }
        }

        if clickMonitor == nil {
            clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                self?.handleMouseDown(at: NSEvent.mouseLocation)
                return event
            }
        }
    }

    private func handleMouseDown(at location: NSPoint) {
        hoverDwellTask?.cancel()

        guard !isExpanded else { return }
        guard isLocationInHoverTriggerBand(location) else { return }

        suppressQuickExpandUntilHoverEnd = true
    }

    private func isLocationInHoverTriggerBand(_ location: NSPoint) -> Bool {
        guard let geometry = displayManager.geometry else { return false }
        return geometry.hoverProximityRect(forExit: false).contains(location)
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .milliseconds(280))
            await MainActor.run {
                guard !self.shouldKeepVisible() else { return }
                if self.hasPriorityLiveActivity {
                    self.suppressAutoShow = false
                    if self.displayManager.geometry != nil {
                        self.presentIdle()
                    }
                    return
                }
                if self.suppressAutoShow {
                    self.dismissImmediately()
                } else if self.wantsIdle, !self.shouldSuppressIdleForMenuOverlap {
                    if self.displayManager.geometry != nil {
                        self.presentIdle()
                    } else {
                        self.dismissImmediately()
                    }
                } else {
                    self.dismissImmediately()
                }
            }
        }
    }

    private func dismissImmediately() {
        hideTask?.cancel()
        hoverExitGraceTask?.cancel()
        hoverDwellTask?.cancel()
        removeEscapeMonitor()
        appState.isIslandInputFocused = false
        appState.cameraMirrorManager.stopPreview()
        isVisible = false
        isExpanded = false
        displayManager.clearMeasuredExpandedHeight()
        syncMediaPolling()
        displayManager.activePanelFrame = nil
        panel?.makeFirstResponder(nil)
        panel?.resignKey()
        panel?.orderOut(nil)
    }

    private func repositionIfVisible(animated: Bool, geometry newGeometry: NotchGeometry? = nil) {
        guard isVisible, let geometry = newGeometry ?? displayManager.geometry, let panel else { return }
        let frame = geometry.frame(
            isExpanded: isExpanded,
            isIdle: !isExpanded,
            idleLeftWingWidth: appState.idleLeftWingWidthOverride,
            idleRightWingWidth: appState.idleRightWingWidthOverride,
            idleBannerWidth: appState.idleDropBannerWidth
        )
        panel.setFrame(frame, animated: animated)
        displayManager.activePanelFrame = frame
    }

    private func refreshView() {
        panel?.updateRootView(makeIslandView())
    }

    private func refreshViewIfVisible() {
        guard isVisible else { return }
        refreshView()
    }

    private func makeIslandView() -> NotchIslandView {
        NotchIslandView(
            isExpanded: isExpanded,
            displayManager: displayManager,
            appState: appState
        )
    }

    func syncMediaPollingState() {
        syncMediaPolling()
    }

    private func syncMediaPolling() {
        appState.mediaMonitor.updateIslandPresentation(
            isVisible: isVisible,
            isExpanded: isExpanded,
            activeModule: appState.activeModule
        )
    }
}
