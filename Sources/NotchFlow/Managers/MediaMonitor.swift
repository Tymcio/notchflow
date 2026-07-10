import Foundation

@MainActor
final class MediaMonitor {
    var onStateChange: ((MediaPlaybackState) -> Void)?

    private let source: MediaSourceProviding
    private let scriptingSource = ScriptingBridgeMediaSource()
    private let lyricsService = LyricsService()
    private var currentState = MediaPlaybackState.empty
    private var lastFetchedArtworkTrackKey: String?

    init(source: MediaSourceProviding = DistributedMediaSource()) {
        self.source = source
    }

    func start() {
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

    private func mergeScriptingState(_ scriptState: MediaPlaybackState) async {
        guard scriptState != .empty else { return }
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
                elapsed: pickTiming(scriptState.elapsed, merged.elapsed),
                duration: pickTiming(scriptState.duration, merged.duration),
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
                elapsed: pickTiming(scriptState.elapsed, merged.elapsed),
                duration: pickTiming(scriptState.duration, merged.duration),
                bundleIdentifier: merged.bundleIdentifier ?? scriptState.bundleIdentifier,
                lyricsSnippet: merged.lyricsSnippet,
                positionSampledAt: Date()
            )
        }
        await applyState(merged)
    }

    private func applyState(_ state: MediaPlaybackState) async {
        var enriched = mergePreservingMediaAssets(incoming: state, current: currentState)

        if enriched.isPlaying, enriched.lyricsSnippet == nil, isPremiumEligible() {
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

        currentState = enriched
        onStateChange?(enriched)
    }

    private func mergePreservingMediaAssets(incoming: MediaPlaybackState, current: MediaPlaybackState) -> MediaPlaybackState {
        let sameTrack = incoming.isSameTrack(as: current)

        let isPlaying = incoming.isPlaying
            || (sameTrack && current.isPlaying && incoming.elapsed > current.elapsed + 0.2)

        let elapsed = pickTiming(incoming.elapsed, current.elapsed)
        let duration = pickTiming(incoming.duration, current.duration)
        let timingUpdated = elapsed != current.elapsed || duration != current.duration

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
            positionSampledAt: timingUpdated ? Date() : current.positionSampledAt
        )
    }

    private func pickTiming(_ incoming: Double, _ current: Double) -> Double {
        if MediaPlaybackState.isUsableTiming(incoming) {
            return incoming
        }
        if MediaPlaybackState.isUsableTiming(current) {
            return current
        }
        return max(incoming, current)
    }

    private func enrichArtworkIfNeeded(_ state: MediaPlaybackState) async -> MediaPlaybackState {
        guard state.title != "Not Playing", !state.title.isEmpty else { return state }

        if lastFetchedArtworkTrackKey == state.trackKey, state.artworkData != nil {
            return state
        }

        let artworkData = await Task.detached { () -> Data? in
            if let url = state.artworkURL, let data = MusicArtworkFetcher.fetchFromURL(url) {
                return data
            }
            return MusicArtworkFetcher.fetch(bundleID: state.bundleIdentifier, trackKey: state.trackKey)
        }.value

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
