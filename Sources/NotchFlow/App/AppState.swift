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
        mediaState.isPlaying && mediaState.title != "Not Playing" && !mediaState.title.isEmpty
    }

    var activeLiveActivity: LiveActivityKind? {
        LiveActivityResolver.resolve(
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

    var shelfBadgeCount: Int {
        shelfItems.count
    }

    var onLiveActivityChange: (() -> Void)?
    var onShelfChange: (() -> Void)?

    func start() async {
        licenseStatus = licenseManager.status
        settings.isPremiumEnabled = isPremium
        await licenseManager.refreshIfNeeded()
        licenseStatus = licenseManager.status
        settings.isPremiumEnabled = isPremium

        mediaMonitor.start()
        hudManager.start()
        focusTimerManager.startMonitoring()
        await calendarManager.ensureAccess()
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
        notificationHub.allowedBundleIDs = Set(settings.allowedNotificationBundleIDs)
        notificationHub.hideMessageBody = settings.hideNotificationBody

        notificationCenterObserver.setEnabled(callsEnabled || notificationsEnabled)
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
            self?.hudState = state
        }

        focusTimerManager.onStateChange = { [weak self] state in
            self?.focusTimerState = state
            self?.notifyLiveActivityChange()
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
            self?.notifyLiveActivityChange()
        }

        notificationHub.onStateChange = { [weak self] in
            guard let self else { return }
            self.hubNotifications = self.notificationHub.recentNotifications
            self.notifyLiveActivityChange()
        }

        notificationCenterObserver.onBannerDetected = { [weak self] banner in
            guard let self else { return }
            self.callManager.handleBanner(banner)
            self.notificationHub.handleBanner(banner)
        }

        notificationCenterObserver.onScanComplete = { [weak self] banners in
            self?.callManager.reconcile(with: banners)
        }
    }
}
