import AppKit
import Foundation

@MainActor
final class MediaMonitor {
    private static let trackedPlayerBundleIDs: Set<String> = [
        "com.spotify.client",
        "com.apple.Music",
        "com.apple.iTunes"
    ]

    var onStateChange: ((MediaPlaybackState) -> Void)?

    private let source: MediaSourceProviding
    private let scriptingSource = ScriptingBridgeMediaSource()
    private let lyricsService = LyricsService()
    private var currentState = MediaPlaybackState.empty
    private var lastFetchedArtworkTrackKey: String?
    private var artworkRequestID = 0
    private var islandVisible = false
    private var islandExpanded = false
    private var activeModule: IslandModule = .media
    private var scriptingPollingActive = false
    private var playerTerminateObserver: NSObjectProtocol?

    init(source: MediaSourceProviding = DistributedMediaSource()) {
        self.source = source
    }

    deinit {
        if let playerTerminateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(playerTerminateObserver)
        }
    }

    func start() {
        registerPlayerTerminationObserver()

        Task {
            await source.startMonitoring { [weak self] state in
                Task { @MainActor in
                    await self?.applyState(state)
                }
            }
        }

        Task {
            await scriptingSource.startMonitoring { [weak self] scriptState in
                Task { @MainActor in
                    await self?.mergeScriptingState(scriptState)
                }
            }
        }
    }

    func updateIslandPresentation(isVisible: Bool, isExpanded: Bool, activeModule: IslandModule) {
        islandVisible = isVisible
        islandExpanded = isExpanded
        self.activeModule = activeModule
        Task {
            await refreshScriptingPolling()
        }
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
        playerTerminateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let bundleID = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? String else {
                    return
                }
                self?.handlePlayerTerminated(bundleID: bundleID)
            }
        }
    }

    private func handlePlayerTerminated(bundleID: String) {
        guard Self.trackedPlayerBundleIDs.contains(bundleID) else { return }
        guard currentState.bundleIdentifier == bundleID else { return }
        Task {
            await applyState(.empty)
        }
    }

    private func mergeScriptingState(_ scriptState: MediaPlaybackState) async {
        if scriptState == .empty {
            if currentState.title != "Not Playing", !currentState.title.isEmpty {
                await applyState(.empty)
            }
            return
        }

        if !scriptState.isPlaying,
           currentState.isPlaying,
           let scriptBundle = scriptState.bundleIdentifier,
           let currentBundle = currentState.bundleIdentifier,
           scriptBundle != currentBundle {
            return
        }

        var merged = currentState
        let sameTrack = scriptState.isSameTrack(as: merged)

        if !scriptState.title.isEmpty, scriptState.title != "Not Playing" {
            merged = MediaPlaybackState(
                title: scriptState.title,
                artist: scriptState.artist,
                album: scriptState.album,
                artworkURL: scriptState.artworkURL ?? (sameTrack ? merged.artworkURL : nil),
                artworkData: scriptState.artworkData ?? (sameTrack ? merged.artworkData : nil),
                isPlaying: scriptState.isPlaying,
                elapsed: MediaPlaybackState.preferredTiming(incoming: scriptState.elapsed, current: merged.elapsed),
                duration: MediaPlaybackState.preferredTiming(incoming: scriptState.duration, current: merged.duration),
                bundleIdentifier: scriptState.bundleIdentifier ?? merged.bundleIdentifier,
                lyricsSnippet: merged.lyricsSnippet,
                positionSampledAt: Date()
            )
        } else if MediaPlaybackState.isUsableTiming(scriptState.elapsed) || MediaPlaybackState.isUsableTiming(scriptState.duration) {
            merged = MediaPlaybackState(
                title: merged.title,
                artist: merged.artist,
                album: merged.album,
                artworkURL: merged.artworkURL,
                artworkData: merged.artworkData,
                isPlaying: scriptState.isPlaying,
                elapsed: MediaPlaybackState.preferredTiming(incoming: scriptState.elapsed, current: merged.elapsed),
                duration: MediaPlaybackState.preferredTiming(incoming: scriptState.duration, current: merged.duration),
                bundleIdentifier: merged.bundleIdentifier ?? scriptState.bundleIdentifier,
                lyricsSnippet: merged.lyricsSnippet,
                positionSampledAt: Date()
            )
        }
        await applyState(merged)
    }

    private func applyState(_ state: MediaPlaybackState) async {
        var enriched = mergePreservingMediaAssets(incoming: state, current: currentState)

        if !enriched.isPlaying,
           currentState.isPlaying,
           let incomingBundle = enriched.bundleIdentifier,
           let currentBundle = currentState.bundleIdentifier,
           incomingBundle != currentBundle,
           enriched.isSameTrack(as: currentState) == false {
            enriched = currentState
        }

        if enriched.isPlaying,
           enriched.lyricsSnippet == nil,
           isPremiumEligible(),
           NotchSettings.shared.lyricsSharingEnabled {
            enriched = MediaPlaybackState(
                title: enriched.title,
                artist: enriched.artist,
                album: enriched.album,
                artworkURL: enriched.artworkURL,
                artworkData: enriched.artworkData,
                isPlaying: enriched.isPlaying,
                elapsed: enriched.elapsed,
                duration: enriched.duration,
                bundleIdentifier: enriched.bundleIdentifier,
                lyricsSnippet: await lyricsService.fetchSnippet(title: enriched.title, artist: enriched.artist),
                positionSampledAt: enriched.positionSampledAt
            )
        }

        let trackChanged = !enriched.isSameTrack(as: currentState)
        if trackChanged {
            lastFetchedArtworkTrackKey = nil
        }

        if enriched.artworkData == nil || trackChanged || lastFetchedArtworkTrackKey != enriched.trackKey {
            enriched = await enrichArtworkIfNeeded(enriched)
        }

        guard enriched != currentState else {
            await refreshScriptingPolling()
            return
        }

        currentState = enriched
        onStateChange?(enriched)
        await refreshScriptingPolling()
    }

    private func refreshScriptingPolling() async {
        let needsPolling = currentState.isPlaying
            && islandVisible
            && islandExpanded
            && activeModule == .media
        guard needsPolling != scriptingPollingActive else { return }
        scriptingPollingActive = needsPolling
        await scriptingSource.setPollingActive(needsPolling)
    }

    private func mergePreservingMediaAssets(incoming: MediaPlaybackState, current: MediaPlaybackState) -> MediaPlaybackState {
        let sameTrack = incoming.isSameTrack(as: current)

        let isPlaying = incoming.isPlaying
            || (incoming.isPlaying && sameTrack && current.isPlaying && incoming.elapsed > current.elapsed + 0.2)

        let elapsed = MediaPlaybackState.preferredTiming(incoming: incoming.elapsed, current: current.elapsed)
        let duration = MediaPlaybackState.preferredTiming(incoming: incoming.duration, current: current.duration)
        let timingUpdated = elapsed != current.elapsed || duration != current.duration
        let playingChanged = isPlaying != current.isPlaying

        return MediaPlaybackState(
            title: incoming.title,
            artist: incoming.artist,
            album: incoming.album,
            artworkURL: incoming.artworkURL ?? (sameTrack ? current.artworkURL : nil),
            artworkData: incoming.artworkData ?? (sameTrack ? current.artworkData : nil),
            isPlaying: isPlaying,
            elapsed: elapsed,
            duration: duration,
            bundleIdentifier: incoming.bundleIdentifier ?? current.bundleIdentifier,
            lyricsSnippet: incoming.lyricsSnippet ?? current.lyricsSnippet,
            positionSampledAt: (timingUpdated || playingChanged) ? Date() : current.positionSampledAt
        )
    }

    private func enrichArtworkIfNeeded(_ state: MediaPlaybackState) async -> MediaPlaybackState {
        guard state.title != "Not Playing", !state.title.isEmpty else { return state }

        if lastFetchedArtworkTrackKey == state.trackKey, state.artworkData != nil {
            return state
        }

        let bundleID = state.bundleIdentifier
        let trackKey = state.trackKey
        let artworkURL = state.artworkURL
        artworkRequestID += 1
        let requestID = artworkRequestID

        let artworkData = await Task.detached(priority: .utility) { () async -> Data? in
            if let url = artworkURL, let data = await MusicArtworkFetcher.fetchFromURL(url) {
                return data
            }
            return await MusicArtworkFetcher.fetch(bundleID: bundleID, trackKey: trackKey)
        }.value

        guard requestID == artworkRequestID, trackKey == currentState.trackKey else { return state }
        guard let artworkData else { return state }

        lastFetchedArtworkTrackKey = state.trackKey

        return MediaPlaybackState(
            title: state.title,
            artist: state.artist,
            album: state.album,
            artworkURL: state.artworkURL,
            artworkData: artworkData,
            isPlaying: state.isPlaying,
            elapsed: state.elapsed,
            duration: state.duration,
            bundleIdentifier: state.bundleIdentifier,
            lyricsSnippet: state.lyricsSnippet,
            positionSampledAt: state.positionSampledAt
        )
    }

    private func isPremiumEligible() -> Bool {
        NotchSettings.shared.isPremiumEnabled
    }
}
