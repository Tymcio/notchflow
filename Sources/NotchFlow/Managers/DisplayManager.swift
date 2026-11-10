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
    @Published private(set) var isFileDragInProgress = false
    @Published private(set) var shouldHideIsland = false

    /// Set by NotchPanelController while the island is visible, so hover keeps it open.
    var activePanelFrame: CGRect?

    var isNotchInteractionActive: Bool {
        isPointerNearNotch || isDragNearNotch
    }

    // Observer and monitor tokens are nonisolated(unsafe): they are only touched on the main
    // actor, and the nonisolated deinit reads them once after the last reference is gone.
    nonisolated(unsafe) private var screenChangeObserver: NSObjectProtocol?
    nonisolated(unsafe) private var workspaceObserver: NSObjectProtocol?
    nonisolated(unsafe) private var mouseMonitor: Any?
    nonisolated(unsafe) private var localMouseMonitor: Any?
    nonisolated(unsafe) private var dragMonitor: Any?
    nonisolated(unsafe) private var localDragMonitor: Any?
    nonisolated(unsafe) private var dragEndMonitor: Any?
    nonisolated(unsafe) private var localDragEndMonitor: Any?
    nonisolated(unsafe) private var localMouseDownMonitor: Any?
    nonisolated(unsafe) private var activationObserver: NSObjectProtocol?
    private let settings: NotchSettings
    private let menuBarLayoutManager: MenuBarLayoutManager
    private var cancellables = Set<AnyCancellable>()
    /// At most one pending task that replays the latest pointer position after throttled events.
    private var trailingMouseMoveTask: Task<Void, Never>?
    private var lastMouseMoveTimestamp: TimeInterval = 0
    private var proximityPollTask: Task<Void, Never>?
    /// Screens and their metrics, rebuilt only when the display configuration changes
    /// (`NSApplication.didChangeScreenParametersNotification`), never per mouse event.
    private var cachedScreens: [CachedScreen] = []
    private var activeScreenEntry: CachedScreen?
    /// Menu bar occupancy for screens without a hardware notch; refreshed on app switches,
    /// screen changes and before the idle island is presented. The scan itself runs off the
    /// main thread; this holds its last result and is updated when a new one lands.
    private var capsuleContext = NotchGeometry.MenuBarContext()
    private var measuredExpandedHeight: CGFloat?
    private var measuredHeightsByModule: [IslandModule: CGFloat] = [:]
    private var baselineDragPasteboardChangeCount = NSPasteboard(name: .drag).changeCount

    private struct CachedScreen {
        let screen: NSScreen
        let frame: CGRect
        let metrics: ScreenMetrics
        let isBuiltIn: Bool
        /// Top band watched by the polling fallback when no global mouse monitor is available.
        let pollBandHeight: CGFloat

        /// Like `frame.contains`, but includes the top edge where the pointer rests in the menu bar.
        func containsPointer(_ location: NSPoint) -> Bool {
            location.x >= frame.minX && location.x < frame.maxX
                && location.y >= frame.minY && location.y <= frame.maxY
        }
    }

    init(settings: NotchSettings, menuBarLayoutManager: MenuBarLayoutManager) {
        self.settings = settings
        self.menuBarLayoutManager = menuBarLayoutManager
        rebuildScreenCache()
        refreshActiveScreen()
        startObservers()
        startWorkspaceObserver()
        bindMenuBarLayout()
        bindSettingsChanges()
    }

    func refreshGeometryNow() {
        refreshActiveScreen()
    }

    deinit {
        trailingMouseMoveTask?.cancel()
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
        if let localMouseDownMonitor {
            NSEvent.removeMonitor(localMouseDownMonitor)
        }
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
        proximityPollTask?.cancel()
    }

    func refreshActiveScreen() {
        let entry = preferredScreenEntry(at: NSEvent.mouseLocation).map(remeasuredIfMenuBarMissing)
        activate(entry)
        menuBarLayoutManager.refresh(for: entry?.screen)
        refreshCapsuleContext()
        recomputeGeometry(for: activeScreen)
    }

    private func activate(_ entry: CachedScreen?) {
        activeScreenEntry = entry
        if activeScreen !== entry?.screen {
            activeScreen = entry?.screen
        }
        menuBarLayoutManager.setActiveScreen(entry?.screen)
    }

    private func rebuildScreenCache() {
        cachedScreens = NSScreen.screens.map { screen in
            let metrics = ScreenMetrics(screen: screen)
            let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            return CachedScreen(
                screen: screen,
                frame: metrics.frame,
                metrics: metrics,
                isBuiltIn: displayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false,
                pollBandHeight: max(
                    metrics.safeAreaTop,
                    metrics.reservedMenuBarHeight,
                    NotchFlowConstants.virtualCapsuleHeight
                )
            )
        }
    }

    private func cachedEntry(for screen: NSScreen?) -> CachedScreen? {
        guard let screen else { return nil }
        return cachedScreens.first { $0.screen === screen }
    }

    /// The display that should host the island for a pointer at `location`, honoring the
    /// "Show the island on" preference.
    private func preferredScreenEntry(at location: NSPoint) -> CachedScreen? {
        switch settings.islandDisplay {
        case .followPointer:
            return cachedScreens.first { $0.containsPointer(location) }
                ?? cachedEntry(for: NSScreen.main)
                ?? cachedScreens.first
        case .mainDisplay:
            // The first screen is the one with the menu bar in System Settings → Displays.
            return cachedScreens.first
        case .builtInDisplay:
            return cachedScreens.first(where: \.isBuiltIn) ?? cachedScreens.first
        }
    }

    private func metrics(for screen: NSScreen) -> ScreenMetrics {
        cachedEntry(for: screen)?.metrics ?? ScreenMetrics(screen: screen)
    }

    /// Reads what sits in the menu bar around the island. Only displays without a hardware notch
    /// draw into the menu bar, so notched MacBooks skip this entirely.
    private func refreshCapsuleContext(forceRescan: Bool = false) {
        guard let screen = activeScreen else {
            capsuleContext = NotchGeometry.MenuBarContext()
            return
        }
        let metrics = metrics(for: screen)
        if case .hardwareNotch = NotchGeometry.classifyTopCutout(metrics) {
            capsuleContext = NotchGeometry.MenuBarContext()
            return
        }
        // Menu bar items only matter when an idle capsule is drawn there.
        let span = settings.nonNotchIslandPlacement.hidesIdleIsland ? nil : NotchGeometry.menuBarCapsuleSpan(for: metrics)
        capsuleContext = menuBarLayoutManager.capsuleContext(
            for: metrics,
            span: span,
            forceRescan: forceRescan
        )
    }

    private func recomputeGeometry(for screen: NSScreen?) {
        guard let screen else {
            if geometry != nil { geometry = nil }
            return
        }
        let metrics = metrics(for: screen)
        let context: NotchGeometry.MenuBarContext
        if case .hardwareNotch = NotchGeometry.classifyTopCutout(metrics) {
            context = NotchGeometry.MenuBarContext(appMenuRightEdgeX: menuBarLayoutManager.menuRightEdgeX(for: screen))
        } else {
            context = capsuleContext
        }
        var nextGeometry = NotchGeometry.make(
            metrics: metrics,
            options: NotchGeometry.Options(settings: settings),
            context: context
        )
        if let measuredExpandedHeight {
            nextGeometry = nextGeometry.withExpandedHeight(measuredExpandedHeight)
        }
        // Publishing an equal value would still re-render every observing view.
        if geometry != nextGeometry {
            geometry = nextGeometry
        }
    }

    func setMeasuredExpandedHeight(_ height: CGFloat, for module: IslandModule) {
        guard height > 0 else { return }
        let clamped = clampExpandedHeight(height.rounded(.up), for: module)
        measuredHeightsByModule[module] = clamped
        applyMeasuredExpandedHeight(clamped)
    }

    func applyIntrinsicExpandedHeight(_ height: CGFloat, for module: IslandModule) {
        guard height > 0 else { return }
        let clamped = clampExpandedHeight(height.rounded(.up), for: module)
        measuredHeightsByModule[module] = clamped
        applyMeasuredExpandedHeight(clamped)
    }

    func setCalendarExpandedHeight(contentHeight: CGFloat) {
        let total = NotchFlowConstants.expandedTotalHeight(forContentHeight: contentHeight)
        guard total > 0 else { return }
        let clamped = clampExpandedHeight(total.rounded(.up), for: .calendar)
        measuredHeightsByModule[.calendar] = max(clamped, measuredHeightsByModule[.calendar] ?? 0)
        let nextHeight = max(clamped, measuredExpandedHeight ?? 0)
        applyMeasuredExpandedHeight(nextHeight)
    }

    func clearDragDropState() {
        isFileDragInProgress = false
        isDragNearNotch = false
        baselineDragPasteboardChangeCount = NSPasteboard(name: .drag).changeCount
    }

    private func applyMeasuredExpandedHeight(_ height: CGFloat) {
        guard measuredExpandedHeight != height else { return }
        measuredExpandedHeight = height
        recomputeGeometry(for: activeScreen)
    }

    func clearMeasuredExpandedHeight() {
        guard measuredExpandedHeight != nil else { return }
        measuredExpandedHeight = nil
        recomputeGeometry(for: activeScreen)
    }

    func applyPreferredExpandedHeight() {
        let preferred = maximumConfiguredExpandedHeight()
        measuredHeightsByModule[.clipboard] = preferred
        applyMeasuredExpandedHeight(preferred)
    }

    func updateExpandedHeight(for module: IslandModule) {
        if module == .calendar {
            let estimated = clampExpandedHeight(module.estimatedTotalExpandedHeight, for: .calendar)
            let cached = measuredHeightsByModule[.calendar] ?? 0
            applyMeasuredExpandedHeight(max(estimated, cached))
            return
        }

        if let cached = measuredHeightsByModule[module] {
            applyMeasuredExpandedHeight(cached)
            return
        }

        if module.prefersIntrinsicExpandedHeight {
            applyMeasuredExpandedHeight(
                clampExpandedHeight(module.estimatedTotalExpandedHeight, for: module)
            )
            return
        }

        applyPreferredExpandedHeight()
    }

    func refreshExpandedHeight(for module: IslandModule) {
        measuredHeightsByModule.removeValue(forKey: module)
        updateExpandedHeight(for: module)
    }

    private func clampExpandedHeight(_ height: CGFloat, for module: IslandModule) -> CGFloat {
        if module.prefersIntrinsicExpandedHeight {
            return clampIntrinsicExpandedHeight(height)
        }
        return clampFixedModuleExpandedHeight(height)
    }

    private func clampIntrinsicExpandedHeight(_ height: CGFloat) -> CGFloat {
        let rounded = height.rounded(.up)
        let minimum = NotchFlowConstants.expandedTotalHeight(
            forContentHeight: NotchFlowConstants.minimumExpandedContentHeight
        )
        let screenMaximum = screenExpandedHeightMaximum()
        return min(max(rounded, minimum), screenMaximum)
    }

    private func clampFixedModuleExpandedHeight(_ height: CGFloat) -> CGFloat {
        let rounded = height.rounded(.up)
        let minimum = NotchFlowConstants.expandedTotalHeight(
            forContentHeight: NotchFlowConstants.minimumExpandedContentHeight
        )
        let configuredMaximum = maximumConfiguredExpandedHeight()
        let screenMaximum = screenExpandedHeightMaximum()
        return min(min(max(rounded, minimum), configuredMaximum), screenMaximum)
    }

    private func screenExpandedHeightMaximum() -> CGFloat {
        ((activeScreen?.visibleFrame.height ?? 800) * 0.7).rounded(.down)
    }

    private func maximumConfiguredExpandedHeight() -> CGFloat {
        let contentCap = settings.isPremiumEnabled
            ? settings.customIslandHeight
            : NotchFlowConstants.maximumExpandedContentHeight
        return NotchFlowConstants.expandedTotalHeight(forContentHeight: contentCap)
    }

    /// Re-reads the app menu edge and rebuilds geometry right before the idle island is presented.
    /// On displays without a notch the menu bar scan is asynchronous: this uses the last scan
    /// and geometry is rebuilt again when a fresher one lands.
    func refreshMenuLayoutNow() {
        menuBarLayoutManager.refresh(for: activeScreen, publishImmediately: true)
        refreshCapsuleContext()
        recomputeGeometry(for: activeScreen)
    }

    private func bindSettingsChanges() {
        settings.onDimensionsChange = { [weak self] in
            self?.recomputeGeometry(for: self?.activeScreen)
        }
        settings.onDisplayPlacementChange = { [weak self] in
            self?.refreshActiveScreen()
        }
    }

    private func bindMenuBarLayout() {
        menuBarLayoutManager.onCapsuleScanUpdate = { [weak self] in
            guard let self else { return }
            self.refreshCapsuleContext()
            self.recomputeGeometry(for: self.activeScreen)
        }
        menuBarLayoutManager.$appMenuRightEdgeX
            .sink { [weak self] _ in
                guard let self else { return }
                if self.geometry?.hasPhysicalNotch == false {
                    // @Published emits before storing; read the new edge on the next turn.
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        self.refreshCapsuleContext()
                        self.recomputeGeometry(for: self.activeScreen)
                    }
                    return
                }
                self.recomputeGeometry(for: self.activeScreen)
            }
            .store(in: &cancellables)
    }

    func updatePointerProximity(at location: NSPoint) {
        guard let geometry else {
            setPointerNearNotch(false)
            return
        }

        let inPanel = activePanelFrame.map { $0.insetBy(dx: -8, dy: -8).contains(location) } ?? false
        if inPanel {
            setPointerNearNotch(true)
            return
        }

        // "Off" on a display without a notch: only the menu bar icon opens the island.
        guard geometry.allowsAutomaticPresentation else {
            setPointerNearNotch(false)
            return
        }

        let triggerRect = geometry.hoverProximityRect(forExit: isPointerNearNotch)
        setPointerNearNotch(triggerRect.contains(location))
    }

    /// Assigning an unchanged value to a @Published property still notifies every subscriber.
    private func setPointerNearNotch(_ isNear: Bool) {
        if isPointerNearNotch != isNear {
            isPointerNearNotch = isNear
        }
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
            DispatchQueue.main.async { [weak self] in
                self?.refreshHideState()
                self?.menuBarLayoutManager.refresh(for: self?.activeScreen, publishImmediately: true)
                self?.refreshCapsuleContext(forceRescan: true)
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
            DispatchQueue.main.async { [weak self] in
                self?.rebuildScreenCache()
                self?.refreshActiveScreen()
            }
        }

        installMouseMonitors()

        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
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

        localMouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self else { return event }
            if !self.isFileDragActive() {
                self.endDragSession()
            }
            return event
        }
    }

    private func handleDrag(at location: NSPoint) {
        guard NSEvent.pressedMouseButtons != 0 else {
            endDragSession()
            return
        }

        guard isFileDragActive() else {
            endDragSession()
            return
        }

        if !isFileDragInProgress {
            isFileDragInProgress = true
        }

        switchActiveScreenIfNeeded(for: location)

        let nearDropZone = isLocationInDragDropZone(location)
        if isDragNearNotch != nearDropZone {
            isDragNearNotch = nearDropZone
        }
        if nearDropZone {
            setPointerNearNotch(true)
        } else {
            updatePointerProximity(at: location)
        }
    }

    private func endDragSession() {
        guard isFileDragInProgress || isDragNearNotch else { return }
        isFileDragInProgress = false
        isDragNearNotch = false
        baselineDragPasteboardChangeCount = NSPasteboard(name: .drag).changeCount
        updatePointerProximity(at: NSEvent.mouseLocation)
    }

    private func isFileDragActive() -> Bool {
        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount != baselineDragPasteboardChangeCount else { return false }
        guard let types = pasteboard.types, !types.isEmpty else { return false }

        let fileTypeStrings: Set<String> = [
            NSPasteboard.PasteboardType.fileURL.rawValue,
            UTType.fileURL.identifier,
            "NSFilenamesPboardType",
            "public.file-url",
        ]

        guard types.contains(where: { fileTypeStrings.contains($0.rawValue) }) else { return false }
        return hasReadableFilePasteboardContent(pasteboard)
    }

    private func hasReadableFilePasteboardContent(_ pasteboard: NSPasteboard) -> Bool {
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], urls.contains(where: \.isFileURL) {
            return true
        }

        let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        if let filenames = pasteboard.propertyList(forType: filenamesType) as? [String],
           !filenames.isEmpty {
            return true
        }

        return false
    }

    private func isLocationInDragDropZone(_ location: NSPoint) -> Bool {
        guard let geometry else { return false }

        let width = geometry.expandedSize.width + NotchFlowConstants.dragDropZoneHorizontalPadding * 2
        let height = geometry.notchTopInset + geometry.expandedSize.height + NotchFlowConstants.dragDropZoneVerticalPadding

        let dropZone: CGRect
        if let notchLeftX = geometry.notchLeftX {
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
            self?.handleMouseMovedEvent(timestamp: event.timestamp)
            return event
        }

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.handleMouseMovedEvent(timestamp: event.timestamp)
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
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.handleMouseMovedEvent(timestamp: event.timestamp)
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
        for entry in cachedScreens {
            let top = entry.frame.maxY
            if location.y >= top - entry.pollBandHeight - NotchFlowConstants.hoverExpandThreshold,
               location.y <= top + 4,
               location.x >= entry.frame.minX, location.x <= entry.frame.maxX {
                return true
            }
        }
        return false
    }

    /// Entry point for every `mouseMoved` event, global or local. It runs for every pointer move
    /// on the Mac, so the common case (pointer far from the island, same display) returns
    /// without allocating, publishing or walking the screen list.
    private func handleMouseMovedEvent(timestamp: TimeInterval) {
        let location = NSEvent.mouseLocation

        if canIgnorePointer(at: location) {
            return
        }

        if isInHoverBand(location) {
            // Inside the menu-bar band: respond immediately for a snappy hover.
            processMouseMove(at: location, timestamp: timestamp)
            return
        }

        guard timestamp - lastMouseMoveTimestamp >= NotchFlowConstants.mouseMoveThrottleInterval else {
            scheduleTrailingMouseMove()
            return
        }
        processMouseMove(at: location, timestamp: timestamp)
    }

    /// Nothing to update: no hover in progress, and the pointer is below every hover target on
    /// the active display (or on another display while the island is pinned to one).
    private func canIgnorePointer(at location: NSPoint) -> Bool {
        guard !isPointerNearNotch, !isDragNearNotch, let entry = activeScreenEntry else { return false }
        guard entry.containsPointer(location) else {
            // A pinned island never moves, so other displays are irrelevant.
            return settings.islandDisplay != .followPointer
        }
        return location.y < interestBandMinY()
    }

    /// Lowest Y on the active display where pointer movement can change hover state.
    private func interestBandMinY() -> CGFloat {
        guard let geometry else { return .greatestFiniteMagnitude }
        var minY = geometry.hoverProximityRect(forExit: true).minY
        if let activePanelFrame {
            minY = min(minY, activePanelFrame.minY - 8)
        }
        return minY
    }

    private func isInHoverBand(_ location: NSPoint) -> Bool {
        guard let geometry else { return false }
        return location.y <= geometry.screenTopY
            && location.y >= geometry.hoverTriggerRect.minY
    }

    private func processMouseMove(at location: NSPoint, timestamp: TimeInterval) {
        lastMouseMoveTimestamp = timestamp
        if trailingMouseMoveTask != nil {
            trailingMouseMoveTask?.cancel()
            trailingMouseMoveTask = nil
        }
        handleMouseMove(location)
    }

    /// Throttled events are not lost: one task replays the latest position after the interval,
    /// so leaving the island quickly still ends hover.
    private func scheduleTrailingMouseMove() {
        guard trailingMouseMoveTask == nil else { return }
        trailingMouseMoveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(NotchFlowConstants.mouseMoveThrottleInterval))
            guard let self, !Task.isCancelled else { return }
            self.trailingMouseMoveTask = nil
            self.lastMouseMoveTimestamp = ProcessInfo.processInfo.systemUptime
            self.handleMouseMove(NSEvent.mouseLocation)
        }
    }

    private func switchActiveScreenIfNeeded(for location: NSPoint) {
        if let entry = activeScreenEntry, entry.containsPointer(location) { return }
        guard settings.islandDisplay == .followPointer,
              let entry = cachedScreens.first(where: { $0.containsPointer(location) }),
              entry.screen !== activeScreen else {
            return
        }
        let current = remeasuredIfMenuBarMissing(entry)
        activate(current)
        menuBarLayoutManager.refresh(for: current.screen)
        refreshCapsuleContext()
        recomputeGeometry(for: current.screen)
    }

    /// A notch-less display that showed no menu bar when it was cached (just connected, or the
    /// menu bar was hidden then) may have one now: measure it again before drawing the capsule.
    /// Runs only when the island moves to such a display, never per mouse move.
    private func remeasuredIfMenuBarMissing(_ entry: CachedScreen) -> CachedScreen {
        guard entry.metrics.safeAreaTop <= 0, entry.metrics.reservedMenuBarHeight <= 0 else { return entry }
        rebuildScreenCache()
        return cachedEntry(for: entry.screen) ?? entry
    }

    private func handleMouseMove(_ location: NSPoint) {
        if isDragNearNotch {
            return
        }

        switchActiveScreenIfNeeded(for: location)
        updatePointerProximity(at: location)
    }
}
