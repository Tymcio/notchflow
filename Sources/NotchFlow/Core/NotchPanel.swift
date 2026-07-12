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
        hostingView.autoresizingMask = [.width, .height]
    }

    func updateRootView(_ rootView: NotchIslandView) {
        hostingView.rootView = rootView
    }

    func activateForInput() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    func setFrame(_ frame: CGRect, animated: Bool) {
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animator().setFrame(frame, display: true)
            }
        } else {
            setFrame(frame, display: true)
        }
    }

    func setIgnoresMouseEvents(_ ignore: Bool) {
        ignoresMouseEvents = ignore
    }

    private func configurePanel() {
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
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
    private var clickMonitor: Any?
    private var escapeMonitor: Any?
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
    }

    deinit {
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
            .sink { [weak self] _ in
                guard let self else { return }
                self.repositionIfVisible(animated: !self.isExpanded)
            }
            .store(in: &cancellables)

        displayManager.$shouldHideIsland
            .sink { [weak self] hidden in
                hidden
                    ? self?.dismissImmediately()
                    : self?.updateVisibility(hovering: self?.displayManager.isNotchInteractionActive ?? false)
            }
            .store(in: &cancellables)
    }

    private func updateVisibility(hovering: Bool) {
        guard !displayManager.shouldHideIsland else {
            dismissImmediately()
            return
        }

        if hovering {
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
            scheduleExpandAfterHoverDwell()
            return
        }

        hoverDwellTask?.cancel()
        suppressQuickExpandUntilHoverEnd = false

        if suppressAutoShow {
            scheduleHide()
            return
        }

        if appState.shouldShowIdleNotch, !shouldHideIdleForMenuOverlap {
            presentIdle()
            return
        }

        scheduleHide()
    }

    private var shouldHideIdleForMenuOverlap: Bool {
        displayManager.geometry?.shouldHideIdleForMenuOverlap == true
    }

    private func handleLiveActivityChange() {
        guard !displayManager.shouldHideIsland else {
            dismissImmediately()
            return
        }

        if isExpanded {
            return
        }

        if displayManager.isNotchInteractionActive {
            refreshViewIfVisible()
            return
        }

        if suppressAutoShow {
            if isVisible {
                dismissImmediately()
            }
            return
        }

        if appState.shouldShowIdleNotch, !shouldHideIdleForMenuOverlap {
            if !isVisible || isExpanded {
                presentIdle()
            } else {
                refreshViewIfVisible()
            }
        } else if isVisible {
            dismissImmediately()
        }
    }

    private func shouldKeepVisible() -> Bool {
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
        panel?.orderFrontRegardless()
        installEscapeMonitorIfNeeded()
    }

    private func presentIdle() {
        displayManager.refreshMenuLayoutNow()
        guard !shouldHideIdleForMenuOverlap else {
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
        panel?.orderFrontRegardless()
        installEscapeMonitorIfNeeded()
    }

    private var idleAcceptsMouseEvents: Bool {
        if case .incomingCall = appState.activeLiveActivity {
            return true
        }
        return false
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
                let frame = geometry.frame(isExpanded: isExpanded, isIdle: !isExpanded)
                panel?.setFrame(frame, animated: false)
            }
        }
    }

    private func keepIdleVisibleIfNeeded() {
        guard appState.shouldShowIdleNotch, !shouldHideIdleForMenuOverlap else { return }
        if !isVisible || isExpanded {
            presentIdle()
        }
    }

    private func scheduleExpandAfterHoverDwell() {
        hoverDwellTask?.cancel()
        keepIdleVisibleIfNeeded()
        hoverDwellTask = Task {
            try? await Task.sleep(
                for: .milliseconds(NotchFlowConstants.hoverExpandDwellMilliseconds)
            )
            await MainActor.run {
                guard !Task.isCancelled else { return }
                guard self.displayManager.isNotchInteractionActive else { return }
                guard !self.suppressQuickExpandUntilHoverEnd else { return }
                if self.displayManager.isFileDragInProgress && self.displayManager.isDragNearNotch {
                    self.appState.activeModule = .shelf
                }
                self.presentExpanded()
            }
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

        let triggerRect: CGRect
        if geometry.hasPhysicalNotch {
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

        return triggerRect.contains(location)
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .milliseconds(280))
            await MainActor.run {
                guard !self.shouldKeepVisible() else { return }
                if self.suppressAutoShow {
                    self.dismissImmediately()
                } else if self.appState.shouldShowIdleNotch, !self.shouldHideIdleForMenuOverlap {
                    self.presentIdle()
                } else {
                    self.dismissImmediately()
                }
            }
        }
    }

    private func dismissImmediately() {
        hideTask?.cancel()
        removeEscapeMonitor()
        appState.isIslandInputFocused = false
        isVisible = false
        isExpanded = false
        displayManager.clearMeasuredExpandedHeight()
        syncMediaPolling()
        displayManager.activePanelFrame = nil
        panel?.makeFirstResponder(nil)
        panel?.resignKey()
        panel?.orderOut(nil)
    }

    private func repositionIfVisible(animated: Bool) {
        guard isVisible, let geometry = displayManager.geometry, let panel else { return }
        let frame = geometry.frame(isExpanded: isExpanded, isIdle: !isExpanded)
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

    private func syncMediaPolling() {
        appState.mediaMonitor.updateIslandPresentation(isVisible: isVisible, isExpanded: isExpanded)
    }
}
