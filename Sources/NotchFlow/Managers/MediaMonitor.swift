import AppKit
import Foundation

/// Publishes the now-playing state. Source updates are merged and published immediately;
/// artwork and lyrics are added afterwards by per-track tasks whose results are cached
/// (hits and misses) and dropped if the track has changed in the meantime.
@MainActor
final class MediaMonitor {
    private static let trackedPlayerBundleIDs: Set<String> = [
        "com.spotify.client",
        "com.apple.Music",
        "com.apple.iTunes"
    ]

    /// How long a failed (network / AppleScript) lookup is remembered before retrying.
    static let failedLookupRetryInterval: TimeInterval = 120

    var onStateChange: ((MediaPlaybackState) -> Void)?

    private let source: MediaSourceProviding
    private let scriptingSource = ScriptingBridgeMediaSource()
    private let lyricsService = LyricsService()
    private var currentState = MediaPlaybackState.empty
    private var islandVisible = false
    private var islandExpanded = false
    private var activeModule: IslandModule = .media
    private var scriptingPollingActive = false
    private var scriptingPollingRequest = 0
    private var playerTerminateObserver: NSObjectProtocol?

    private var artworkCache = MediaEnrichmentCache<Data>(capacity: 32)
    private var lyricsCache = MediaEnrichmentCache<String>(capacity: 64)
    private var artworkTask: (key: String, task: Task<Void, Never>)?
    private var lyricsTask: (key: String, task: Task<Void, Never>)?

    init(source: MediaSourceProviding = DistributedMediaSource()) {
        self.source = source
    }

    func start() {
        registerPlayerTerminationObserver()

        let sourceHandler: @Sendable (MediaPlaybackState) -> Void = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.applyState(state)
            }
        }
        let scriptingHandler: @Sendable (MediaPlaybackState) -> Void = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.mergeScriptingState(state)
            }
        }
        let source = source
        let scriptingSource = scriptingSource
        Task { await source.startMonitoring(handler: sourceHandler) }
        Task { await scriptingSource.startMonitoring(handler: scriptingHandler) }
    }

    func updateIslandPresentation(isVisible: Bool, isExpanded: Bool, activeModule: IslandModule) {
        islandVisible = isVisible
        islandExpanded = isExpanded
        self.activeModule = activeModule
        refreshScriptingPolling()
    }

    func togglePlayPause() {
        MediaPlayerController.perform(.playPause, playerBundleID: currentState.bundleIdentifier)
    }

    func nextTrack() {
        MediaPlayerController.perform(.next, playerBundleID: currentState.bundleIdentifier)
    }

    func previousTrack() {
        MediaPlayerController.perform(.previous, playerBundleID: currentState.bundleIdentifier)
    }

    func seek(to position: Double) {
        MediaPlayerController.seek(to: position, playerBundleID: currentState.bundleIdentifier)
    }

    private func registerPlayerTerminationObserver() {
        guard playerTerminateObserver == nil else { return }
        playerTerminateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let bundleID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                .bundleIdentifier else { return }
            MainActor.assumeIsolated {
                self?.handlePlayerTerminated(bundleID: bundleID)
            }
        }
    }

    private func handlePlayerTerminated(bundleID: String) {
        guard Self.trackedPlayerBundleIDs.contains(bundleID) else { return }
        guard currentState.bundleIdentifier == bundleID else { return }
        applyState(.empty)
    }

    private func mergeScriptingState(_ scriptState: MediaPlaybackState) {
        if scriptState == .empty {
            if currentState.hasActiveTrack {
                applyState(.empty)
            }
            return
        }
        guard let merged = MediaStateMerger.mergeScripting(scriptState, into: currentState) else { return }
        applyState(merged)
    }

    // MARK: - Publishing

    private func applyState(_ state: MediaPlaybackState) {
        // Full-size artwork from a source never goes into the published state; it is
        // downsampled off the main actor first.
        let rawArtwork = state.artworkData
        var merged = MediaStateMerger.merge(incoming: state.with(artworkData: nil), current: currentState)

        if MediaStateMerger.isStaleOtherPlayer(merged, current: currentState) {
            merged = currentState
        }

        if merged.hasActiveTrack {
            let key = merged.trackKey
            if let artwork = artworkCache.value(for: key) {
                merged = merged.with(artworkData: artwork)
            }
            if merged.lyricsSnippet == nil, let lyrics = lyricsCache.value(for: key) {
                merged = merged.with(lyricsSnippet: lyrics)
            }
        }

        publish(merged)
        scheduleEnrichment(for: merged, rawArtwork: merged.artworkData == nil ? rawArtwork : nil)
        refreshScriptingPolling()
    }

    private func publish(_ state: MediaPlaybackState) {
        guard state != currentState else { return }
        currentState = state
        onStateChange?(state)
    }

    private func refreshScriptingPolling() {
        let needsPolling = currentState.isPlaying
            && islandVisible
            && islandExpanded
            && activeModule == .media
        guard needsPolling != scriptingPollingActive else { return }
        scriptingPollingActive = needsPolling
        scriptingPollingRequest += 1
        let request = scriptingPollingRequest
        let scriptingSource = scriptingSource
        Task {
            // Tasks may start out of order; the source ignores superseded requests.
            await scriptingSource.setPollingActive(needsPolling, request: request)
        }
    }

    // MARK: - Enrichment

    private func scheduleEnrichment(for state: MediaPlaybackState, rawArtwork: Data?) {
        guard state.hasActiveTrack else {
            cancelEnrichment()
            return
        }
        let key = state.trackKey
        if artworkTask?.key != key {
            artworkTask?.task.cancel()
            artworkTask = nil
        }
        if lyricsTask?.key != key {
            lyricsTask?.task.cancel()
            lyricsTask = nil
        }

        if state.artworkData == nil, artworkTask == nil,
           rawArtwork != nil || artworkCache.lookup(key) == nil {
            startArtworkTask(for: state, key: key, rawArtwork: rawArtwork)
        }

        if state.isPlaying,
           state.lyricsSnippet == nil,
           lyricsTask == nil,
           lyricsCache.lookup(key) == nil,
           NotchSettings.shared.isPremiumEnabled,
           NotchSettings.shared.lyricsSharingEnabled {
            startLyricsTask(for: state, key: key)
        }
    }

    private func startArtworkTask(for state: MediaPlaybackState, key: String, rawArtwork: Data?) {
        let artworkURL = state.artworkURL
        let bundleID = state.bundleIdentifier
        let task = Task.detached(priority: .utility) { [weak self] in
            let data = await MusicArtworkFetcher.artwork(
                rawData: rawArtwork,
                artworkURL: artworkURL,
                bundleID: bundleID,
                trackKey: key
            )
            guard !Task.isCancelled else { return }
            await self?.finishArtwork(data, key: key)
        }
        artworkTask = (key, task)
    }

    private func finishArtwork(_ data: Data?, key: String) {
        if artworkTask?.key == key { artworkTask = nil }
        artworkCache.store(data, for: key, ttl: data == nil ? Self.failedLookupRetryInterval : nil)
        guard let data, currentState.trackKey == key, currentState.artworkData == nil else { return }
        publish(currentState.with(artworkData: data))
    }

    private func startLyricsTask(for state: MediaPlaybackState, key: String) {
        let title = state.title
        let artist = state.artist
        let service = lyricsService
        let task = Task { [weak self] in
            let result = await service.lookup(title: title, artist: artist)
            guard !Task.isCancelled else { return }
            self?.finishLyrics(result, key: key)
        }
        lyricsTask = (key, task)
    }

    private func finishLyrics(_ result: LyricsLookup, key: String) {
        if lyricsTask?.key == key { lyricsTask = nil }
        switch result {
        case .found(let line):
            lyricsCache.store(line, for: key)
        case .notFound:
            lyricsCache.store(nil, for: key)
        case .failed:
            lyricsCache.store(nil, for: key, ttl: Self.failedLookupRetryInterval)
        }
        guard case .found(let line) = result,
              currentState.trackKey == key,
              currentState.lyricsSnippet == nil else { return }
        publish(currentState.with(lyricsSnippet: line))
    }

    private func cancelEnrichment() {
        artworkTask?.task.cancel()
        artworkTask = nil
        lyricsTask?.task.cancel()
        lyricsTask = nil
    }
}
