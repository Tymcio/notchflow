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
    /// Wymusza odświeżenie widoku idle po zmianie połączenia (CallManager nie jest @Observable).
    private(set) var callLiveActivityRevision = 0

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
    let callManager: CallManager
    let notificationHub: NotificationHubManager
    let notificationCenterObserver: NotificationCenterObserver

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
        callManager = CallManager()
        notificationHub = NotificationHubManager()
        notificationCenterObserver = NotificationCenterObserver()
        bindManagers()
    }

    var isPremium: Bool {
        !LicenseMode.current.isEnforced || licenseStatus.isPremium
    }

    var showsMediaIdle: Bool {
        mediaState.isPlaying && mediaState.hasActiveTrack
    }

    var activeLiveActivity: LiveActivityKind? {
        _ = callLiveActivityRevision
        return LiveActivityResolver.resolve(
            incomingCall: callManager.incomingCall,
            activeCall: callManager.activeCall,
            timer: focusTimerState.showsInIdleNotch ? focusTimerState.activity : nil,
            notification: notificationHub.peek,
            showsMedia: showsMediaIdle
        )
    }

    var shouldShowIdleNotch: Bool {
        activeLiveActivity != nil
    }

    /// Active-call peeks widen the right wing so content is readable.
    var idleRightWingWidthOverride: CGFloat? {
        switch activeLiveActivity {
        case .activeCall(let call):
            let displayName = NotificationAppCatalog.isSystemCallUILabel(call.callerName)
                ? loc("Incoming call")
                : call.callerName
            return IdleCallMetrics.preferredRightWingWidth(
                callerName: displayName,
                actionButtonCount: 1,
                showsSubtitle: true
            )
        case .timer(let timer) where timer.isFinished && timer.isAlertMuted:
            return IdleTimerMetrics.preferredMutedRightWingWidth()
        default:
            return nil
        }
    }

    /// Incoming calls and app notifications hang below the cutout (not wing peeks).
    var idleDropBannerWidth: CGFloat? {
        let cutout = displayManager.geometry?.physicalNotchCutoutWidth
            ?? NotchFlowConstants.defaultNotchCutoutWidth
        switch activeLiveActivity {
        case .incomingCall(let call):
            return IncomingCallBannerMetrics.preferredWidth(for: call, cutoutWidth: cutout)
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
        let content: CGFloat
        switch activeLiveActivity {
        case .incomingCall:
            content = NotchFlowConstants.incomingCallDropContentHeight
        default:
            content = NotchFlowConstants.dropBannerContentHeight
        }
        return NotchFlowConstants.dropBannerHeight(topInset: topInset, contentHeight: content)
    }

    var idleDropBannerTopInset: CGFloat {
        displayManager.geometry?.notchTopInset
            ?? displayManager.geometry?.idleSize.height
            ?? 32
    }

    /// Kept for call sites that still name the call banner specifically.
    var idleIncomingCallBannerWidth: CGFloat? {
        idleDropBannerWidth
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

        if settings.localAPIEnabled {
            do {
                try await localAPIServer.start(appState: self)
            } catch {
                NotchFlowLog.api.error("Failed to start local API: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func applyNotificationSettings() {
        let callsEnabled = isPremium && settings.callsInNotchEnabled
        let notificationsEnabled = isPremium && settings.appNotificationsEnabled

        callManager.isEnabled = callsEnabled
        notificationHub.isEnabled = notificationsEnabled
        notificationHub.allowedNativeBundleIDs = Set(settings.allowedNativeNotificationBundleIDs)
        notificationHub.hideMessageBody = settings.hideNotificationBody

        notificationCenterObserver.setEnabled(
            callsEnabled || notificationsEnabled,
            callsPriority: callsEnabled
        )
        notificationCenterObserver.callSessionActiveProvider = { [weak self] in
            self?.callManager.needsFrequentScan == true
        }
        notifyLiveActivityChange()
    }

    func answerIncomingCall() {
        callManager.answerCall(using: notificationCenterObserver)
        notifyLiveActivityChange()
    }

    func declineIncomingCall() {
        callManager.declineCall(using: notificationCenterObserver)
        notifyLiveActivityChange()
    }

    func endActiveCall() {
        callManager.endCall(using: notificationCenterObserver)
        notifyLiveActivityChange()
    }

    func openHubNotificationApp() {
        notificationHub.openActivePeekApp()
        notifyLiveActivityChange()
    }

    func replyToHubNotification(_ text: String) {
        if !notificationHub.replyToActivePeek(text: text, using: notificationCenterObserver) {
            notificationHub.openActivePeekApp()
        }
        notifyLiveActivityChange()
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
        }

        callManager.onStateChange = { [weak self] in
            guard let self else { return }
            self.callLiveActivityRevision += 1
            self.notifyLiveActivityChange()
        }

        notificationHub.onStateChange = { [weak self] in
            guard let self else { return }
            self.hubNotifications = self.notificationHub.recentNotifications
            self.notifyLiveActivityChange()
        }

        notificationCenterObserver.onBannerDetected = { [weak self] banner in
            guard let self else { return }
            if banner.isLikelyCall {
                guard self.isPremium, self.settings.callsInNotchEnabled else { return }
                self.callManager.handleBanner(banner)
                return
            }

            let shownInNotch = self.notificationHub.handleBanner(banner)
            if shownInNotch, self.settings.dismissSystemBanners {
                self.notificationCenterObserver.dismissBanner(banner)
            }
        }

        notificationCenterObserver.onScanComplete = { [weak self] banners in
            self?.callManager.reconcile(with: banners)
        }
    }
}
