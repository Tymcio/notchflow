import AppKit
import ApplicationServices
import Combine
import Foundation
import os

@MainActor
final class MenuBarLayoutManager: ObservableObject {
    private static let logger = Logger(subsystem: NotchFlowConstants.bundleID, category: "MenuBarLayout")

    @Published private(set) var appMenuRightEdgeX: CGFloat?
    @Published private(set) var isAccessibilityTrusted = AXIsProcessTrusted()

    private var workspaceObserver: NSObjectProtocol?
    private var delayedRefreshTask: Task<Void, Never>?
    private let settings: NotchSettings
    private weak var activeScreen: NSScreen?

    init(settings: NotchSettings) {
        self.settings = settings
        settings.onAvoidMenuOverlapChange = { [weak self] in
            self?.refresh()
        }
        startObservers()
        refresh()
    }

    deinit {
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        delayedRefreshTask?.cancel()
    }

    func setActiveScreen(_ screen: NSScreen?) {
        activeScreen = screen
    }

    func refresh(for screen: NSScreen? = nil) {
        if let screen {
            activeScreen = screen
        }

        isAccessibilityTrusted = AXIsProcessTrusted()

        guard settings.avoidMenuOverlap, isAccessibilityTrusted else {
            Self.logger.debug("refresh skipped: avoidOverlap=\(self.settings.avoidMenuOverlap) trusted=\(self.isAccessibilityTrusted)")
            appMenuRightEdgeX = nil
            return
        }

        guard let app = NSWorkspace.shared.frontmostApplication else {
            appMenuRightEdgeX = nil
            return
        }

        let pid = app.processIdentifier
        guard pid != ProcessInfo.processInfo.processIdentifier else {
            // Our own panel briefly became frontmost; keep the last known edge
            // so the wing doesn't pop back to full width.
            return
        }

        let newEdge = Self.readLeftMenuClusterRightEdgeX(
            for: pid,
            leftMenuBounds: activeScreen?.auxiliaryTopLeftArea
        )
        Self.logger.debug("refresh app=\(app.localizedName ?? "?", privacy: .public) edge=\(newEdge.map(String.init(describing:)) ?? "nil", privacy: .public)")
        if newEdge != appMenuRightEdgeX {
            appMenuRightEdgeX = newEdge
        }
    }

    func requestPermission() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        isAccessibilityTrusted = AXIsProcessTrustedWithOptions(options)
        refresh()
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func menuRightEdgeX(for screen: NSScreen) -> CGFloat? {
        guard settings.avoidMenuOverlap, isAccessibilityTrusted else { return nil }
        guard let edge = appMenuRightEdgeX else { return nil }

        let screenFrame = screen.frame
        guard edge >= screenFrame.minX, edge <= screenFrame.maxX else { return nil }
        return edge
    }

    private func startObservers() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
                self?.scheduleDelayedRefresh()
            }
        }
    }

    private func scheduleDelayedRefresh() {
        delayedRefreshTask?.cancel()
        delayedRefreshTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.refresh()
            }
        }
    }

    /// Right edge of the last menu item in the left cluster (before the notch).
    static func readLeftMenuClusterRightEdgeX(for pid: pid_t, leftMenuBounds: CGRect?) -> CGFloat? {
        let appElement = AXUIElementCreateApplication(pid)

        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
              let menuBarRef else {
            return nil
        }
        let menuBar = menuBarRef as! AXUIElement

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menuBar, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let childrenRef else {
            return nil
        }

        // `as? [AXUIElement]` on a CFArray of AXUIElements is unreliable; verify each element by type ID.
        let children = ((childrenRef as! NSArray) as Array).compactMap { item -> AXUIElement? in
            let object = item as CFTypeRef
            guard CFGetTypeID(object) == AXUIElementGetTypeID() else { return nil }
            return (object as! AXUIElement)
        }
        guard !children.isEmpty else {
            return nil
        }

        let leftClusterMaxX = leftMenuBounds?.maxX
        var maxRightX: CGFloat = 0
        var foundVisible = false

        for child in children {
            guard let frame = axFrame(for: child) else { continue }
            guard frame.width >= 12, frame.height >= 10 else { continue }
            guard !isHidden(child) else { continue }

            if let leftClusterMaxX {
                // Ignore items on the right side of the notch (e.g. Help, Window).
                guard frame.midX <= leftClusterMaxX + NotchFlowConstants.menuBarItemClusterFudge else {
                    continue
                }
            }

            let rightX = frame.maxX
            if rightX > maxRightX {
                maxRightX = rightX
                foundVisible = true
            }
        }

        guard foundVisible else { return nil }
        return maxRightX
    }

    private static func isHidden(_ element: AXUIElement) -> Bool {
        var hiddenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXHiddenAttribute as CFString, &hiddenRef) == .success,
           let hidden = hiddenRef as? Bool, hidden {
            return true
        }
        return false
    }

    private static func axFrame(for element: AXUIElement) -> CGRect? {
        guard let origin = axValuePoint(for: element, attribute: kAXPositionAttribute as CFString),
              let size = axValueSize(for: element, attribute: kAXSizeAttribute as CFString),
              size.width > 0, size.height > 0 else {
            return nil
        }

        return CGRect(origin: origin, size: size)
    }

    private static func axValuePoint(for element: AXUIElement, attribute: CFString) -> CGPoint? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &valueRef) == .success,
              let valueRef else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetValue(valueRef as! AXValue, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    private static func axValueSize(for element: AXUIElement, attribute: CFString) -> CGSize? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &valueRef) == .success,
              let valueRef else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(valueRef as! AXValue, .cgSize, &size) else {
            return nil
        }
        return size
    }
}
