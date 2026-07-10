import AppKit
import Foundation

/// ScriptingBridge-backed media source for Spotify and Apple Music.
/// Falls back gracefully when automation permission is denied.
final class ScriptingBridgeMediaSource: MediaSourceProviding, @unchecked Sendable {
    private var handler: (@Sendable (MediaPlaybackState) -> Void)?
    private var pollTask: Task<Void, Never>?
    private var latestState = MediaPlaybackState.empty

    func startMonitoring(handler: @escaping @Sendable (MediaPlaybackState) -> Void) async {
        self.handler = handler
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                let state = await fetchState()
                if state != latestState {
                    latestState = state
                    handler(state)
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
        handler(latestState)
    }

    func stopMonitoring() async {
        pollTask?.cancel()
        pollTask = nil
        handler = nil
    }

    func togglePlayPause() async {
        MediaPlayerController.perform(.playPause, playerBundleID: latestState.bundleIdentifier)
    }

    func nextTrack() async {
        MediaPlayerController.perform(.next, playerBundleID: latestState.bundleIdentifier)
    }

    func previousTrack() async {
        MediaPlayerController.perform(.previous, playerBundleID: latestState.bundleIdentifier)
    }

    func seek(to position: Double) async {
        MediaPlayerController.seek(to: position, playerBundleID: latestState.bundleIdentifier)
    }

    private func fetchState() async -> MediaPlaybackState {
        if let spotify = fetchSpotifyState() { return spotify }
        if let music = fetchMusicState() { return music }
        return latestState == .empty ? .empty : latestState
    }

    private func fetchSpotifyState() -> MediaPlaybackState? {
        guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == "com.spotify.client" }) else {
            return nil
        }
        let script = """
        tell application "Spotify"
            if player state is playing or player state is paused then
                set trackName to name of current track
                set artistName to artist of current track
                set albumName to album of current track
                set playerState to player state as string
                set trackDuration to duration of current track
                set playerPosition to player position
                return trackName & "|||" & artistName & "|||" & albumName & "|||" & playerState & "|||" & (trackDuration as string) & "|||" & (playerPosition as string)
            end if
        end tell
        """
        return enrichWithArtwork(parseScriptResult(script, bundleID: "com.spotify.client"))
    }

    private func fetchMusicState() -> MediaPlaybackState? {
        guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == "com.apple.Music" }) else {
            return nil
        }
        let script = """
        tell application "Music"
            if player state is playing or player state is paused then
                set trackName to name of current track
                set artistName to artist of current track
                set albumName to album of current track
                set playerState to player state as string
                set trackDuration to duration of current track
                set playerPosition to player position
                return trackName & "|||" & artistName & "|||" & albumName & "|||" & playerState & "|||" & (trackDuration as string) & "|||" & (playerPosition as string)
            end if
        end tell
        """
        return enrichWithArtwork(parseScriptResult(script, bundleID: "com.apple.Music"))
    }

    private func enrichWithArtwork(_ state: MediaPlaybackState?) -> MediaPlaybackState? {
        guard var state else { return nil }

        let trackKey = state.trackKey
        guard let artworkData = MusicArtworkFetcher.fetch(bundleID: state.bundleIdentifier, trackKey: trackKey) else {
            return MediaPlaybackState(
                title: state.title,
                artist: state.artist,
                album: state.album,
                artworkURL: state.artworkURL,
                artworkData: nil,
                isPlaying: state.isPlaying,
                elapsed: state.elapsed,
                duration: state.duration,
                bundleIdentifier: state.bundleIdentifier,
                lyricsSnippet: state.lyricsSnippet
            )
        }

        state = MediaPlaybackState(
            title: state.title,
            artist: state.artist,
            album: state.album,
            artworkURL: state.artworkURL,
            artworkData: artworkData,
            isPlaying: state.isPlaying,
            elapsed: state.elapsed,
            duration: state.duration,
            bundleIdentifier: state.bundleIdentifier,
            lyricsSnippet: state.lyricsSnippet
        )
        return state
    }

    private func parseScriptResult(_ script: String, bundleID: String) -> MediaPlaybackState? {
        guard let output = runAppleScriptReturningString(script) else { return nil }
        let parts = output.components(separatedBy: "|||")
        guard parts.count >= 6 else { return nil }

        let isPlaying = parts[3].lowercased() == "playing"
        let rawDuration = Double(parts[4]) ?? 0
        let duration = bundleID == "com.spotify.client" ? rawDuration / 1000.0 : rawDuration
        let elapsed = Double(parts[5]) ?? 0

        return MediaPlaybackState(
            title: parts[0],
            artist: parts[1],
            album: parts[2],
            artworkURL: nil,
            artworkData: nil,
            isPlaying: isPlaying,
            elapsed: elapsed,
            duration: duration > 0 ? duration : latestState.duration,
            bundleIdentifier: bundleID,
            lyricsSnippet: nil
        )
    }

    private func runAppleScriptReturningString(_ script: String) -> String? {
        guard let appleScript = NSAppleScript(source: script) else { return nil }
        var error: NSDictionary?
        guard let output = appleScript.executeAndReturnError(&error).stringValue else { return nil }
        return output
    }
}
