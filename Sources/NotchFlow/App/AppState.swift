import Foundation
import SwiftUI

@MainActor
@Observable
final class AppState {
    var activeModule: IslandModule = .media
    var mediaState = MediaPlaybackState.empty
    var shelfItems: [ShelfItem] = []
    var hudState: HUDOverlayState?
    var focusTimerState = FocusTimerState()
    var upcomingEvent: CalendarEventPreview?
    var dayEvents: [CalendarEventPreview] = []
    var calendarAccessGranted = false
    var notes: [NoteItem] = []
    var clipboardEntries: [ClipboardEntry] = []
    var licenseStatus: LicenseStatus = .free
    var isIslandInputFocused = false
    var hubNotifications: [HubNotification] = []
    /// Wymusza odświeżenie idle po zmianie sesji agentów.
    private(set) var agentLiveActivityRevision = 0
    /// Wymusza odświeżenie idle / zakładki Agents po zmianie limitów Claude/Codex.
    private(set) var agentUsageRevision = 0

    let mediaMonitor: MediaMonitor
    let shelfManager: ShelfManager
    let hudManager: HUDManager
    let focusTimerManager: FocusTimerManager
    let calendarManager: CalendarManager
    let licenseManager: LicenseManager
    let displayManager: DisplayManager
    let menuBarLayoutManager: MenuBarLayoutManager
    var settings: NotchSettings
    let notesManager: NotesManager
    let clipboardManager: ClipboardManager
    let cameraMirrorManager: CameraMirrorManager
    let localAPIServer: LocalAPIServer
    let notificationHub: NotificationHubManager
    let notificationCenterObserver: NotificationCenterObserver
    let agentSessionManager: AgentSessionManager
    let agentUsageMonitor: AgentUsageMonitor

    init() {
        let sharedSettings = NotchSettings.shared
        settings = sharedSettings
        let menuBarLayoutManager = MenuBarLayoutManager(settings: sharedSettings)
        self.menuBarLayoutManager = menuBarLayoutManager
        displayManager = DisplayManager(settings: sharedSettings, menuBarLayoutManager: menuBarLayoutManager)
        mediaMonitor = MediaMonitor()
        shelfManager = ShelfManager()
        hudManager = HUDManager()
        focusTimerManager = FocusTimerManager()
        calendarManager = CalendarManager()
        licenseManager = LicenseManager()
        notesManager = NotesManager()
        clipboardManager = ClipboardManager()
        cameraMirrorManager = CameraMirrorManager()
        localAPIServer = LocalAPIServer()
        notificationHub = NotificationHubManager()
        notificationCenterObserver = NotificationCenterObserver()
        agentSessionManager = AgentSessionManager()
        agentUsageMonitor = AgentUsageMonitor()
        bindManagers()
    }

    var isPremium: Bool {
        !LicenseMode.current.isEnforced || licenseStatus.isPremium
    }

    var hasAgentsAddon: Bool {
        !LicenseMode.current.isEnforced || licenseStatus.hasAgentsAddon
    }

    var showsMediaIdle: Bool {
        mediaState.isPlaying && mediaState.hasActiveTrack
    }

    var activeLiveActivity: LiveActivityKind? {
        _ = agentLiveActivityRevision
        return LiveActivityResolver.resolve(
            agentSession: hasAgentsAddon ? agentSessionManager.primaryActivity : nil,
            timer: focusTimerState.showsInIdleNotch ? focusTimerState.activity : nil,
            notification: notificationHub.peek,
            showsMedia: showsMediaIdle
        )
    }

    var shouldShowIdleNotch: Bool {
        activeLiveActivity != nil
    }

    /// Agent peeks widen the left wing so names like "Cursor" stay clear of the notch.
    var idleLeftWingWidthOverride: CGFloat? {
        switch activeLiveActivity {
        case .agentSession:
            return IdleAgentMetrics.preferredLeftWingWidth
        default:
            return nil
        }
    }

    /// Agent and muted-timer peeks widen the right wing so content is readable.
    var idleRightWingWidthOverride: CGFloat? {
        switch activeLiveActivity {
        case .agentSession(let session):
            return IdleAgentMetrics.preferredRightWingWidth(
                needsAttention: session.needsAttention
            )
        case .timer(let timer) where timer.isFinished && timer.isAlertMuted:
            return IdleTimerMetrics.preferredMutedRightWingWidth()
        default:
            return nil
        }
    }

    /// App notifications hang below the cutout (not wing peeks).
    var idleDropBannerWidth: CGFloat? {
        let cutout = displayManager.geometry?.physicalNotchCutoutWidth
            ?? NotchFlowConstants.defaultNotchCutoutWidth
        switch activeLiveActivity {
        case .notification(let peek):
            return NotificationBannerMetrics.preferredWidth(for: peek, cutoutWidth: cutout)
        default:
            return nil
        }
    }

    var idleDropBannerHeight: CGFloat? {
        guard idleDropBannerWidth != nil else { return nil }
        let topInset = displayManager.geometry?.notchTopInset
            ?? displayManager.geometry?.idleSize.height
            ?? 32
        return NotchFlowConstants.dropBannerHeight(
            topInset: topInset,
            contentHeight: NotchFlowConstants.dropBannerContentHeight
        )
    }

    var idleDropBannerTopInset: CGFloat {
        displayManager.geometry?.notchTopInset
            ?? displayManager.geometry?.idleSize.height
            ?? 32
    }

    var shelfBadgeCount: Int {
        shelfItems.count
    }

    var onLiveActivityChange: (() -> Void)?
    var onShelfChange: (() -> Void)?

    func updateMeasuredExpandedIslandSize(_ size: CGSize, module: IslandModule) {
        displayManager.setMeasuredExpandedHeight(size.height, for: module)
    }

    func start() async {
        licenseStatus = licenseManager.status
        settings.isPremiumEnabled = isPremium
        await licenseManager.refreshIfNeeded()
        licenseManager.startObservingSystemEvents()
        licenseStatus = licenseManager.status
        settings.isPremiumEnabled = isPremium
        displayManager.refreshGeometryNow()

        mediaMonitor.start()
        hudManager.start()
        focusTimerManager.startMonitoring()
        // Only read the current status here; the system prompt is shown from the
        // calendar tab's "Udziel dostępu" button, where the user expects it.
        await calendarManager.refreshAccessStatus()
        calendarAccessGranted = calendarManager.hasAccess
        if calendarManager.hasAccess {
            calendarManager.startAutoRefresh()
        }
        clipboardManager.setMonitoringEnabled(settings.clipboardMonitoringEnabled)
        notes = notesManager.notes
        shelfItems = shelfManager.items
        clipboardEntries = clipboardManager.entries
        hubNotifications = notificationHub.recentNotifications
        applyNotificationSettings()
        applyAgentUsagePolling()

        if settings.localAPIEnabled {
            do {
                try await localAPIServer.start(appState: self)
            } catch {
                NotchFlowLog.api.error("Failed to start local API: \(error.localizedDescription, privacy: .public)")
            }
            // Keep installed agent hook script in sync with the running app build.
            if AgentHooksInstaller.currentStatus(localAPIEnabled: true).hookScriptInstalled {
                try? AgentHooksInstaller.refreshBundledScript()
            }
        }
    }

    func applyNotificationSettings() {
        let notificationsEnabled = isPremium && settings.appNotificationsEnabled
        notificationHub.isEnabled = notificationsEnabled
        notificationHub.allowedNativeBundleIDs = Set(settings.allowedNativeNotificationBundleIDs)
        notificationHub.hideMessageBody = settings.hideNotificationBody

        notificationCenterObserver.setEnabled(notificationsEnabled)
        notifyLiveActivityChange()
    }

    func applyAgentUsagePolling() {
        agentUsageMonitor.setEnabled(hasAgentsAddon && settings.agentUsagePollingEnabled)
    }

    func allowActiveAgentPermission() {
        guard let permission = agentSessionManager.sessions.compactMap(\.permission).first else { return }
        agentSessionManager.decidePermission(id: permission.id, decision: .allow)
    }

    func denyActiveAgentPermission() {
        guard let permission = agentSessionManager.sessions.compactMap(\.permission).first else { return }
        agentSessionManager.decidePermission(id: permission.id, decision: .deny)
    }

    func jumpToActiveAgentSession() {
        guard let session = agentSessionManager.sessions.first else { return }
        agentSessionManager.jump(to: session)
        activeModule = .agents
    }

    func openHubNotificationApp() {
        notificationHub.openActivePeekApp()
        notifyLiveActivityChange()
    }

    func replyToHubNotification(_ text: String) {
        let peekID = notificationHub.peek?.id
        Task { @MainActor in
            // The AX reply runs off the main thread; only fall back to opening the app if the
            // same notification is still shown.
            if await !notificationHub.replyToActivePeek(text: text, using: notificationCenterObserver),
               notificationHub.peek?.id == peekID {
                notificationHub.openActivePeekApp()
            }
            notifyLiveActivityChange()
        }
    }

    func setClipboardMonitoringEnabled(_ enabled: Bool) {
        settings.clipboardMonitoringEnabled = enabled
        clipboardManager.setMonitoringEnabled(enabled)
        if enabled {
            clipboardManager.captureIfChanged()
        }
    }

    func openSettings(tab: SettingsTab = .general) {
        SettingsWindowController.shared.show(appState: self, tab: tab)
    }

    func openIntegrationsSettings() {
        openSettings(tab: .integrations)
    }

    func openLicenseSettings() {
        openSettings(tab: .license)
    }

    func openNotificationsSettings() {
        openSettings(tab: .notifications)
    }

    func handleURL(_ url: URL) {
        URLSchemeHandler.handle(url: url, appState: self)
    }

    private func notifyLiveActivityChange() {
        onLiveActivityChange?()
    }

    /// Used by Local API / hooks to refresh island chrome after agent events.
    func notifyAgentActivityChange() {
        agentLiveActivityRevision += 1
        notifyLiveActivityChange()
    }

    private func bindManagers() {
        mediaMonitor.onStateChange = { [weak self] state in
            self?.mediaState = state
            self?.notifyLiveActivityChange()
        }

        shelfManager.onItemsChange = { [weak self] items in
            self?.shelfItems = items
            self?.onShelfChange?()
        }

        hudManager.onHUDChange = { [weak self] state in
            withAnimation(.easeOut(duration: 0.2)) {
                self?.hudState = state
            }
        }

        focusTimerManager.onStateChange = { [weak self] state in
            guard let self else { return }
            let previousShowsInIdle = self.focusTimerState.showsInIdleNotch
            let previousFinished = self.focusTimerState.isFinished
            let previousMuted = self.focusTimerState.isAlertMuted
            self.focusTimerState = state
            if state.showsInIdleNotch != previousShowsInIdle
                || state.isFinished != previousFinished
                || state.isAlertMuted != previousMuted {
                self.notifyLiveActivityChange()
            }
        }

        calendarManager.onEventChange = { [weak self] event in
            self?.upcomingEvent = event
        }

        calendarManager.onDayEventsChange = { [weak self] events in
            self?.dayEvents = events
        }

        calendarManager.onAccessChange = { [weak self] granted in
            self?.calendarAccessGranted = granted
        }

        notesManager.onNotesChange = { [weak self] notes in
            self?.notes = notes
        }

        clipboardManager.onEntriesChange = { [weak self] entries in
            self?.clipboardEntries = entries
        }

        licenseManager.onStatusChange = { [weak self] status in
            guard let self else { return }
            self.licenseStatus = status
            self.settings.isPremiumEnabled = self.isPremium
            self.applyNotificationSettings()
            self.applyAgentUsagePolling()
        }

        agentSessionManager.onStateChange = { [weak self] in
            guard let self else { return }
            self.agentLiveActivityRevision += 1
            self.notifyLiveActivityChange()
            if self.hasAgentsAddon, self.settings.agentUsagePollingEnabled {
                Task { await self.agentUsageMonitor.refresh(force: false) }
            }
        }

        agentUsageMonitor.onChange = { [weak self] in
            guard let self else { return }
            self.agentUsageRevision += 1
            self.notifyLiveActivityChange()
        }

        // Real Claude-style consent: jump so the prompt is visible.
        // Cursor jump-only heuristics are often false positives — pulse the notch, don't steal focus.
        agentSessionManager.onNeedsAttention = { [weak self] session in
            guard session.showsNotchApproval else { return }
            self?.agentSessionManager.jumpIfNeeded(for: session)
        }

        notificationHub.onStateChange = { [weak self] in
            guard let self else { return }
            self.hubNotifications = self.notificationHub.recentNotifications
            self.notifyLiveActivityChange()
        }

        // Call banners never reach this callback — the observer drops them, because
        // Continuity has no public API for caller identity or Answer/Decline.
        notificationCenterObserver.onBannerDetected = { [weak self] banner in
            guard let self else { return }
            let shownInNotch = self.notificationHub.handleBanner(banner)
            if shownInNotch, self.settings.dismissSystemBanners {
                self.notificationCenterObserver.dismissBanner(banner)
            }
        }
    }
}
