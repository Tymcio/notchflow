import AppKit
import Combine
import QuartzCore
import SwiftUI

@MainActor
final class NotchPanel: NSPanel {
    private let hostingView: NSHostingView<NotchIslandView>

    init(rootView: NotchIslandView) {
        hostingView = NSHostingView(rootView: rootView)
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        configurePanel()
        contentView = hostingView
    }

    func updateRootView(_ rootView: NotchIslandView) {
        hostingView.rootView = rootView
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

@MainActor
final class NotchPanelController: ObservableObject {
    @Published private(set) var isExpanded = false
    @Published private(set) var isVisible = false

    private var panel: NotchPanel?
    private var hideTask: Task<Void, Never>?
    private var forceVisibleUntil: Date?
    private let displayManager: DisplayManager
    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()

    init(displayManager: DisplayManager, appState: AppState) {
        self.displayManager = displayManager
        self.appState = appState
        appState.onMediaStateChange = { [weak self] in
            self?.handleMediaStateChange()
        }
        bind()
    }

    func showFromMenu() {
        forceVisibleUntil = Date().addingTimeInterval(8)
        presentExpanded()
    }

    private func bind() {
        displayManager.$isPointerNearNotch
            .removeDuplicates()
            .sink { [weak self] isNear in
                self?.updateVisibility(hovering: isNear)
            }
            .store(in: &cancellables)

        displayManager.$geometry
            .sink { [weak self] _ in
                self?.repositionIfVisible(animated: true)
                self?.refreshViewIfVisible()
            }
            .store(in: &cancellables)

        displayManager.$shouldHideIsland
            .sink { [weak self] hidden in
                hidden ? self?.dismissImmediately() : self?.updateVisibility(hovering: self?.displayManager.isPointerNearNotch ?? false)
            }
            .store(in: &cancellables)

        // Refresh idle visibility when playback state changes
        Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, !self.isExpanded else { return }
                self.updateIdleVisibility()
            }
            .store(in: &cancellables)
    }

    private func updateVisibility(hovering: Bool) {
        guard !displayManager.shouldHideIsland else {
            dismissImmediately()
            return
        }

        if hovering || shouldForceVisible() {
            hideTask?.cancel()
            presentExpanded()
            return
        }

        if appState.shouldShowIdleNotch {
            presentIdle()
            return
        }

        scheduleHide()
    }

    private func updateIdleVisibility() {
        guard !isExpanded, !displayManager.isPointerNearNotch, !shouldForceVisible() else { return }
        handleMediaStateChange()
    }

    private func handleMediaStateChange() {
        guard !displayManager.shouldHideIsland else {
            dismissImmediately()
            return
        }

        if isExpanded || shouldForceVisible() || displayManager.isPointerNearNotch {
            return
        }

        if appState.shouldShowIdleNotch {
            if !isVisible || isExpanded {
                presentIdle()
            }
        } else if isVisible {
            dismissImmediately()
        }
    }

    private func shouldForceVisible() -> Bool {
        if let forceVisibleUntil, Date() < forceVisibleUntil { return true }
        forceVisibleUntil = nil
        return false
    }

    private func shouldKeepVisible() -> Bool {
        if shouldForceVisible() { return true }
        if displayManager.isPointerNearNotch { return true }
        if let panel, panel.isVisible, panel.frame.insetBy(dx: -8, dy: -8).contains(NSEvent.mouseLocation) {
            return true
        }
        return false
    }

    private func presentExpanded() {
        ensurePanel()
        let needsRefresh = !isVisible || !isExpanded
        isExpanded = true
        isVisible = true
        if needsRefresh {
            refreshView()
        }
        repositionIfVisible(animated: needsRefresh)
        panel?.orderFrontRegardless()
    }

    private func presentIdle() {
        ensurePanel()
        let needsRefresh = !isVisible || isExpanded
        isExpanded = false
        isVisible = true
        if needsRefresh {
            refreshView()
        }
        repositionIfVisible(animated: needsRefresh)
        panel?.orderFrontRegardless()
    }

    private func ensurePanel() {
        if panel == nil {
            panel = NotchPanel(rootView: makeIslandView())
        }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .milliseconds(280))
            await MainActor.run {
                guard !self.shouldKeepVisible() else { return }
                if self.appState.shouldShowIdleNotch {
                    self.presentIdle()
                } else {
                    self.dismissImmediately()
                }
            }
        }
    }

    private func dismissImmediately() {
        hideTask?.cancel()
        isVisible = false
        isExpanded = false
        displayManager.activePanelFrame = nil
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
            geometry: displayManager.geometry,
            appState: appState
        )
    }
}
