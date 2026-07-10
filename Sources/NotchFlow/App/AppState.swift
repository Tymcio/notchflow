import Foundation
import SwiftUI

@MainActor
@Observable
final class AppState {
    var activeModule: IslandModule = .media
    var mediaState = MediaPlaybackState.empty
    var shelfItems: [ShelfItem] = []
    var hudState: HUDOverlayState?
    var pomodoroState = PomodoroState()
    var upcomingEvent: CalendarEventPreview?
    var dayEvents: [CalendarEventPreview] = []
    var notes: [NoteItem] = []
    var clipboardEntries: [ClipboardEntry] = []
    var licenseStatus: LicenseStatus = .free

    let mediaMonitor: MediaMonitor
    let shelfManager: ShelfManager
    let hudManager: HUDManager
    let pomodoroManager: PomodoroManager
    let calendarManager: CalendarManager
    let licenseManager: LicenseManager
    let displayManager: DisplayManager
    var settings: NotchSettings
    let notesManager: NotesManager
    let clipboardManager: ClipboardManager
    let cameraMirrorManager: CameraMirrorManager
    let localAPIServer: LocalAPIServer

    init() {
        let sharedSettings = NotchSettings.shared
        settings = sharedSettings
        displayManager = DisplayManager(settings: sharedSettings)
        mediaMonitor = MediaMonitor()
        shelfManager = ShelfManager()
        hudManager = HUDManager()
        pomodoroManager = PomodoroManager()
        calendarManager = CalendarManager()
        licenseManager = LicenseManager()
        notesManager = NotesManager()
        clipboardManager = ClipboardManager()
        cameraMirrorManager = CameraMirrorManager()
        localAPIServer = LocalAPIServer()
        bindManagers()
    }

    var isPremium: Bool {
        licenseStatus.isPremium
    }

    var shouldShowIdleNotch: Bool {
        mediaState.isPlaying && mediaState.title != "Not Playing" && !mediaState.title.isEmpty
    }

    var onMediaStateChange: (() -> Void)?

    func start() async {
        settings.isPremiumEnabled = licenseManager.status.isPremium
        await licenseManager.refreshIfNeeded()
        settings.isPremiumEnabled = licenseManager.status.isPremium
        licenseStatus = licenseManager.status

        mediaMonitor.start()
        hudManager.start()
        pomodoroManager.start()
        calendarManager.startAutoRefresh()
        clipboardManager.setMonitoringEnabled(settings.clipboardMonitoringEnabled)
        notes = notesManager.notes
        shelfItems = shelfManager.items
        clipboardEntries = clipboardManager.entries

        if settings.localAPIEnabled {
            try? await localAPIServer.start(appState: self)
        }
    }

    func openSettings() {
        SettingsWindowController.shared.show(appState: self)
    }

    func handleURL(_ url: URL) {
        URLSchemeHandler.handle(url: url, appState: self)
    }

    private func bindManagers() {
        mediaMonitor.onStateChange = { [weak self] state in
            self?.mediaState = state
            self?.onMediaStateChange?()
        }

        shelfManager.onItemsChange = { [weak self] items in
            self?.shelfItems = items
        }

        hudManager.onHUDChange = { [weak self] state in
            self?.hudState = state
        }

        pomodoroManager.onStateChange = { [weak self] state in
            self?.pomodoroState = state
        }

        calendarManager.onEventChange = { [weak self] event in
            self?.upcomingEvent = event
        }

        calendarManager.onDayEventsChange = { [weak self] events in
            self?.dayEvents = events
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
            self.settings.isPremiumEnabled = status.isPremium
        }
    }
}

import AppKit
