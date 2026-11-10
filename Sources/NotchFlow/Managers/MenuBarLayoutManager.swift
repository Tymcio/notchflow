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

    // nonisolated(unsafe): only touched on the main actor; the nonisolated deinit reads it once
    // after the last reference is gone.
    nonisolated(unsafe) private var workspaceObserver: NSObjectProtocol?
    private var capsuleScanCache: CapsuleScan?
    private var pendingCapsuleScan: CapsuleScanRequest?
    private var capsuleScanDebounceTask: Task<Void, Never>?
    private var isCapsuleScanRunning = false
    /// Called on the main actor after a background menu bar scan stored a new result.
    var onCapsuleScanUpdate: (() -> Void)?
    private var delayedRefreshTask: Task<Void, Never>?
    private var menuEdgePublishTask: Task<Void, Never>?
    private var menuEdgeByPID: [pid_t: CGFloat] = [:]
    private var lastForegroundAppPID: pid_t?
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
        menuEdgePublishTask?.cancel()
        capsuleScanDebounceTask?.cancel()
    }

    func setActiveScreen(_ screen: NSScreen?) {
        activeScreen = screen
    }

    func refresh(for screen: NSScreen? = nil, publishImmediately: Bool = false) {
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

        let selfPID = ProcessInfo.processInfo.processIdentifier
        let pid = app.processIdentifier
        let menuPID: pid_t
        if pid == selfPID || app.activationPolicy != .regular {
            // System dialogs (e.g. TCC permission prompts) and background agents own no
            // menu bar; querying them via AX blocks the main thread until timeout.
            guard let lastForegroundAppPID else { return }
            menuPID = lastForegroundAppPID
        } else {
            lastForegroundAppPID = pid
            menuPID = pid
            if publishImmediately, let cachedEdge = menuEdgeByPID[menuPID] {
                if appMenuRightEdgeX != cachedEdge {
                    appMenuRightEdgeX = cachedEdge
                }
            }
        }

        let newEdge = Self.readLeftMenuClusterRightEdgeX(
            for: menuPID,
            leftMenuBounds: activeScreen?.auxiliaryTopLeftArea
        )
        Self.logger.debug(
            "refresh app=\(app.localizedName ?? "?", privacy: .public) menuPID=\(menuPID) edge=\(newEdge.map(String.init(describing:)) ?? "nil", privacy: .public)"
        )
        if let newEdge {
            menuEdgeByPID[menuPID] = newEdge
            applyMenuEdge(newEdge, publishImmediately: publishImmediately)
        } else if menuEdgeByPID[menuPID] == nil {
            applyMenuEdge(nil, publishImmediately: publishImmediately)
        }
    }

    private func applyMenuEdge(_ newEdge: CGFloat?, publishImmediately: Bool) {
        if publishImmediately {
            menuEdgePublishTask?.cancel()
            if newEdge != appMenuRightEdgeX {
                appMenuRightEdgeX = newEdge
            }
            return
        }

        publishMenuEdge(newEdge)
    }

    private func publishMenuEdge(_ newEdge: CGFloat?) {
        menuEdgePublishTask?.cancel()
        menuEdgePublishTask = Task {
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if newEdge != self.appMenuRightEdgeX {
                    self.appMenuRightEdgeX = newEdge
                }
            }
        }
    }

    func requestPermission() {
        // Value of `kAXTrustedCheckOptionPrompt`; reading the C global is not concurrency-safe.
        let promptKey = "AXTrustedCheckOptionPrompt"
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
        menuRightEdgeX(inScreenFrame: screen.frame)
    }

    func menuRightEdgeX(inScreenFrame screenFrame: CGRect) -> CGFloat? {
        guard settings.avoidMenuOverlap, isAccessibilityTrusted else { return nil }
        guard let edge = appMenuRightEdgeX else { return nil }

        guard edge >= screenFrame.minX, edge <= screenFrame.maxX else { return nil }
        return edge
    }

    // MARK: - Menu bar around an island drawn into the menu bar (displays without a notch)

    /// What a background menu bar scan looks at. Equal requests within `capsuleScanLifetime`
    /// reuse the cached result.
    private struct CapsuleScanRequest: Equatable, Sendable {
        let screenFrame: CGRect
        let menuPID: pid_t?
        /// `nil` when menu bar items are not needed (only the full-screen check runs).
        let span: ClosedRange<CGFloat>?
        /// Height of the primary display, to convert to the top-left origin used by AX and
        /// the window server. Read on the main thread, since `NSScreen` is main-thread only.
        let primaryMaxY: CGFloat
        let menuBarScreenY: CGFloat

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.screenFrame == rhs.screenFrame && lhs.menuPID == rhs.menuPID && lhs.span == rhs.span
        }
    }

    private struct CapsuleScan: Sendable {
        let request: CapsuleScanRequest
        let date: Date
        let isFullScreenActive: Bool
        /// When the hit-test could not run (our own panel in the way), the edges carry over
        /// the previous answer for this display.
        let appMenuRightEdgeX: CGFloat?
        let statusItemsLeftEdgeX: CGFloat?
    }

    /// How long a menu bar scan stays valid while the frontmost app does not change.
    private static let capsuleScanLifetime: TimeInterval = 2
    /// Coalesces bursts of requests (app switch + screen switch + idle presentation).
    private static let capsuleScanDebounce: Duration = .milliseconds(60)
    /// Accessibility hit-tests and the window list are IPC; they never run on the main thread.
    private static let capsuleScanQueue = DispatchQueue(label: "\(NotchFlowConstants.bundleID).menu-bar-scan", qos: .utility)

    /// Menu bar occupancy for an island drawn into the menu bar of `metrics`' display.
    /// `span` is the x-range the island may cover (`NotchGeometry.menuBarCapsuleSpan`);
    /// pass `nil` when nothing is drawn into the menu bar there.
    ///
    /// Returns the last scan for this display right away and, when it is missing or stale,
    /// schedules a scan on a background queue; `onCapsuleScanUpdate` fires when it lands.
    func capsuleContext(
        for metrics: ScreenMetrics,
        span: ClosedRange<CGFloat>?,
        forceRescan: Bool = false
    ) -> NotchGeometry.MenuBarContext {
        var context = NotchGeometry.MenuBarContext(
            appMenuRightEdgeX: menuRightEdgeX(inScreenFrame: metrics.frame)
        )

        let wantsMenuItems = span != nil
            && settings.avoidMenuOverlap
            && isAccessibilityTrusted
            && metrics.reservedMenuBarHeight > 0
        let request = CapsuleScanRequest(
            screenFrame: metrics.frame,
            menuPID: lastForegroundAppPID,
            span: wantsMenuItems ? span : nil,
            primaryMaxY: NSScreen.screens.first?.frame.maxY ?? metrics.frame.maxY,
            menuBarScreenY: metrics.frame.maxY - metrics.reservedMenuBarHeight / 2
        )

        let cached = capsuleScanCache?.request.screenFrame == metrics.frame ? capsuleScanCache : nil
        if forceRescan
            || cached == nil
            || cached?.request != request
            || Date().timeIntervalSince(cached?.date ?? .distantPast) >= Self.capsuleScanLifetime {
            scheduleCapsuleScan(request)
        }

        guard let cached else { return context }
        context.isFullScreenActive = cached.isFullScreenActive
        guard wantsMenuItems, !cached.isFullScreenActive, cached.request.span != nil else {
            return context
        }
        // Status items do not depend on the frontmost app; its menus do.
        context.statusItemsLeftEdgeX = cached.statusItemsLeftEdgeX
        if cached.request.menuPID == request.menuPID, let scannedEdge = cached.appMenuRightEdgeX {
            context.appMenuRightEdgeX = max(context.appMenuRightEdgeX ?? scannedEdge, scannedEdge)
        }
        return context
    }

    private func scheduleCapsuleScan(_ request: CapsuleScanRequest) {
        pendingCapsuleScan = request
        guard capsuleScanDebounceTask == nil, !isCapsuleScanRunning else { return }
        capsuleScanDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.capsuleScanDebounce)
            guard let self, !Task.isCancelled else { return }
            self.capsuleScanDebounceTask = nil
            self.startPendingCapsuleScan()
        }
    }

    private func startPendingCapsuleScan() {
        guard let request = pendingCapsuleScan, !isCapsuleScanRunning else { return }
        pendingCapsuleScan = nil
        isCapsuleScanRunning = true
        Self.capsuleScanQueue.async { [weak self] in
            let isFullScreen = Self.isFullScreenWindowPresent(on: request.screenFrame, primaryMaxY: request.primaryMaxY)
            var items: [MenuBarItemHit]?
            if let span = request.span, !isFullScreen {
                items = Self.menuBarItems(in: span, atScreenY: request.menuBarScreenY, primaryMaxY: request.primaryMaxY)
            }
            let outcome = CapsuleScanOutcome(isFullScreenActive: isFullScreen, items: items)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.finishCapsuleScan(request, outcome: outcome)
                }
            }
        }
    }

    private struct CapsuleScanOutcome: Sendable {
        let isFullScreenActive: Bool
        /// `nil` when the hit-test was skipped or NotchFlow's own panel was in the way.
        let items: [MenuBarItemHit]?
    }

    private func finishCapsuleScan(_ request: CapsuleScanRequest, outcome: CapsuleScanOutcome) {
        isCapsuleScanRunning = false
        let previous = capsuleScanCache?.request.screenFrame == request.screenFrame ? capsuleScanCache : nil
        let appMenuEdge: CGFloat?
        let statusEdge: CGFloat?
        if let items = outcome.items {
            appMenuEdge = items.filter { !$0.isStatusItem }.map(\.frame.maxX).max()
            statusEdge = items.filter(\.isStatusItem).map(\.frame.minX).min()
        } else {
            // Our own panel was in the way (or nothing was hit-tested); keep the last answer
            // for this display.
            appMenuEdge = previous?.appMenuRightEdgeX
            statusEdge = previous?.statusItemsLeftEdgeX
        }
        capsuleScanCache = CapsuleScan(
            request: request,
            date: Date(),
            isFullScreenActive: outcome.isFullScreenActive,
            appMenuRightEdgeX: appMenuEdge,
            statusItemsLeftEdgeX: statusEdge
        )
        onCapsuleScanUpdate?()
        // A request that arrived while this scan ran.
        if pendingCapsuleScan != nil, capsuleScanDebounceTask == nil {
            startPendingCapsuleScan()
        }
    }

    private struct MenuBarItemHit: Sendable {
        let frame: CGRect
        let isStatusItem: Bool
    }

    /// Per-element Accessibility timeout for menu bar hit-test results. Set on each element, never
    /// on the system-wide element: that would change the default for every AX call in the process.
    nonisolated private static let hitTestElementTimeout: Float = 0.05
    /// A scan that takes longer than this (a busy app answering hit-tests slowly) is abandoned.
    nonisolated private static let hitTestBudget: TimeInterval = 0.5

    /// Hit-tests the menu bar along `span` (screen coordinates) and returns the menu bar items found.
    /// Status items belong to many processes, so asking each for its extras menu bar would be slow;
    /// a handful of position queries across the island's span is cheap and finds both app menus
    /// and status items. Returns `nil` when NotchFlow's own panel covers part of the span or the
    /// scan ran out of time. Runs on `capsuleScanQueue`.
    nonisolated private static func menuBarItems(
        in span: ClosedRange<CGFloat>,
        atScreenY screenY: CGFloat,
        primaryMaxY: CGFloat
    ) -> [MenuBarItemHit]? {
        let systemWide = AXUIElementCreateSystemWide()
        let ownPID = ProcessInfo.processInfo.processIdentifier
        // Accessibility uses a top-left origin on the primary display.
        let axY = Float(primaryMaxY - screenY)
        let step: CGFloat = 8
        let deadline = Date().addingTimeInterval(hitTestBudget)

        var hits: [MenuBarItemHit] = []
        var x = span.lowerBound
        while x <= span.upperBound {
            guard Date() < deadline else { return nil }
            var elementRef: AXUIElement?
            guard AXUIElementCopyElementAtPosition(systemWide, Float(x), axY, &elementRef) == .success,
                  let element = elementRef else {
                x += step
                continue
            }
            if pid(of: element) == ownPID {
                return nil
            }
            guard let item = menuBarItem(containing: element) else {
                x += step
                continue
            }
            guard let frame = axFrame(for: item), frame.width > 0 else {
                x += step
                continue
            }
            let subrole = stringAttribute(kAXSubroleAttribute as CFString, of: item)
            // AX frames use a top-left origin; only x matters here, which is shared.
            hits.append(MenuBarItemHit(frame: frame, isStatusItem: subrole == "AXMenuExtra"))
            x = max(x + step, frame.maxX + 1)
        }
        return hits
    }

    /// The element itself or its closest menu bar item ancestor (hit-tests may land on a child image).
    nonisolated private static func menuBarItem(containing element: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = element
        for _ in 0..<3 {
            guard let candidate = current else { return nil }
            AXUIElementSetMessagingTimeout(candidate, hitTestElementTimeout)
            let role = stringAttribute(kAXRoleAttribute as CFString, of: candidate)
            if role == (kAXMenuBarItemRole as String) {
                return candidate
            }
            // Empty menu bar space: nothing above it can be an item.
            if role == (kAXMenuBarRole as String) || role == (kAXApplicationRole as String) {
                return nil
            }
            var parentRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(candidate, kAXParentAttribute as CFString, &parentRef) == .success,
                  let parentRef,
                  CFGetTypeID(parentRef) == AXUIElementGetTypeID() else {
                return nil
            }
            current = (parentRef as! AXUIElement)
        }
        return nil
    }

    nonisolated private static func pid(of element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        return AXUIElementGetPid(element, &pid) == .success ? pid : nil
    }

    nonisolated private static func stringAttribute(_ attribute: CFString, of element: AXUIElement) -> String? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &valueRef) == .success else { return nil }
        return valueRef as? String
    }

    /// True when another app shows a window covering the whole display (a full-screen Space or a
    /// borderless full-screen window), in which case the menu bar only slides in on demand.
    /// Window server IPC; runs on `capsuleScanQueue`.
    nonisolated static func isFullScreenWindowPresent(on screenFrame: CGRect, primaryMaxY: CGFloat) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return false
        }
        // Window bounds use a top-left origin on the primary display.
        let target = CGRect(
            x: screenFrame.minX,
            y: primaryMaxY - screenFrame.maxY,
            width: screenFrame.width,
            height: screenFrame.height
        )
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return windows.contains { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? pid_t) != ownPID,
                  let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary) else {
                return false
            }
            return abs(bounds.minX - target.minX) <= 1
                && abs(bounds.minY - target.minY) <= 1
                && abs(bounds.width - target.width) <= 1
                && abs(bounds.height - target.height) <= 1
        }
    }

    private func startObservers() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.scheduleAppActivationRefreshes()
            }
        }
    }

    private func scheduleAppActivationRefreshes() {
        delayedRefreshTask?.cancel()
        refresh(publishImmediately: true)

        delayedRefreshTask = Task {
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.refresh(publishImmediately: true)
            }
        }
    }

    /// Right edge of the last menu item in the left cluster (before the notch).
    nonisolated static func readLeftMenuClusterRightEdgeX(for pid: pid_t, leftMenuBounds: CGRect?) -> CGFloat? {
        let appElement = AXUIElementCreateApplication(pid)
        // These reads run on the main thread; never wait long for an unresponsive process.
        AXUIElementSetMessagingTimeout(appElement, 0.25)

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
            guard frame.width <= NotchFlowConstants.menuBarItemMaxWidth else { continue }
            guard !isHidden(child) else { continue }

            if let leftClusterMaxX {
                // Ignore items on the right side of the notch (e.g. Help, Window).
                guard frame.midX <= leftClusterMaxX + NotchFlowConstants.menuBarItemClusterFudge else {
                    continue
                }
                // Reject Accessibility frames that span the whole bar (common in Electron apps).
                guard frame.maxX <= leftClusterMaxX + NotchFlowConstants.menuBarItemClusterFudge + 24 else {
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

    nonisolated private static func isHidden(_ element: AXUIElement) -> Bool {
        var hiddenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXHiddenAttribute as CFString, &hiddenRef) == .success,
           let hidden = hiddenRef as? Bool, hidden {
            return true
        }
        return false
    }

    nonisolated private static func axFrame(for element: AXUIElement) -> CGRect? {
        guard let origin = axValuePoint(for: element, attribute: kAXPositionAttribute as CFString),
              let size = axValueSize(for: element, attribute: kAXSizeAttribute as CFString),
              size.width > 0, size.height > 0 else {
            return nil
        }

        return CGRect(origin: origin, size: size)
    }

    nonisolated private static func axValuePoint(for element: AXUIElement, attribute: CFString) -> CGPoint? {
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

    nonisolated private static func axValueSize(for element: AXUIElement, attribute: CFString) -> CGSize? {
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
