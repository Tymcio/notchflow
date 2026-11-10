import AppKit
import Foundation

/// Track fields read from one player by AppleScript (numbers come back unlocalized).
struct ScriptedTrack: Equatable, Sendable {
    let title: String
    let artist: String
    let album: String
    let playerState: String
    /// Spotify reports milliseconds, Music seconds.
    let rawDuration: Double
    let position: Double

    /// Parses the `{name, artist, album, state, duration, position}` list the poll scripts return.
    init?(descriptor: NSAppleEventDescriptor) {
        guard descriptor.numberOfItems >= 6 else { return nil }
        func string(_ index: Int) -> String {
            descriptor.atIndex(index)?.stringValue ?? ""
        }
        func number(_ index: Int) -> Double {
            descriptor.atIndex(index).map { $0.doubleValue } ?? 0
        }
        self.init(
            title: string(1),
            artist: string(2),
            album: string(3),
            playerState: string(4),
            rawDuration: number(5),
            position: number(6)
        )
    }

    init(title: String, artist: String, album: String, playerState: String, rawDuration: Double, position: Double) {
        self.title = title
        self.artist = artist
        self.album = album
        self.playerState = playerState
        self.rawDuration = rawDuration
        self.position = position
    }

    func playbackState(bundleID: String, fallbackDuration: Double, sampledAt: Date = Date()) -> MediaPlaybackState? {
        guard !title.isEmpty else { return nil }
        let duration = bundleID == ScriptedPlayer.spotify.bundleID ? rawDuration / 1000.0 : rawDuration
        let resolvedDuration = duration.isFinite && duration > 0 ? duration : fallbackDuration
        let elapsed = position.isFinite ? position : 0
        return MediaPlaybackState(
            title: title,
            artist: artist,
            album: album,
            artworkURL: nil,
            artworkData: nil,
            isPlaying: playerState.lowercased() == "playing",
            elapsed: max(0, elapsed),
            duration: max(0, resolvedDuration),
            bundleIdentifier: bundleID,
            lyricsSnippet: nil,
            positionSampledAt: sampledAt
        )
    }
}

enum ScriptedPlayer: CaseIterable, Sendable {
    case spotify
    case music

    var bundleID: String {
        switch self {
        case .spotify: "com.spotify.client"
        case .music: "com.apple.Music"
        }
    }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// One compiled script per player; returns `{}` when nothing is loaded.
    var pollScript: String {
        let name = self == .spotify ? "Spotify" : "Music"
        return """
        if application "\(name)" is running then
            with timeout of 3 seconds
                tell application "\(name)"
                    if player state is playing or player state is paused then
                        return {name of current track, artist of current track, album of current track, player state as string, duration of current track, player position}
                    end if
                end tell
            end timeout
        end if
        return {}
        """
    }
}

/// AppleScript-backed timing supplement for Spotify and Apple Music.
/// Polls only while `MediaMonitor` asks for it (expanded media module, playing) and only
/// queries players that are running; otherwise distributed notifications drive the UI.
actor ScriptingBridgeMediaSource: MediaSourceProviding {
    static let pollInterval: Duration = .milliseconds(750)

    private var handler: (@Sendable (MediaPlaybackState) -> Void)?
    private var pollTask: Task<Void, Never>?
    private var isPolling = false
    private var lastPollingRequest = 0
    private var latestState = MediaPlaybackState.empty
    private let executor: AppleScriptExecutor

    init(executor: AppleScriptExecutor = .shared) {
        self.executor = executor
    }

    func startMonitoring(handler: @escaping @Sendable (MediaPlaybackState) -> Void) async {
        self.handler = handler
        let initial = await fetchState()
        latestState = initial
        if initial != .empty {
            handler(initial)
        }
    }

    func stopMonitoring() async {
        setPollingActive(false)
        handler = nil
    }

    /// `request` increases with every caller-side change; stale (reordered) requests are ignored.
    func setPollingActive(_ active: Bool, request: Int? = nil) {
        if let request {
            guard request > lastPollingRequest else { return }
            lastPollingRequest = request
        }
        guard active != isPolling else { return }
        isPolling = active
        pollTask?.cancel()
        pollTask = nil
        guard active else { return }

        pollTask = Task {
            while !Task.isCancelled {
                await pollOnce()
                try? await Task.sleep(for: Self.pollInterval, tolerance: .milliseconds(100))
            }
        }
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

    private func pollOnce() async {
        let state = await fetchState()
        guard isPolling, !Task.isCancelled else { return }
        if shouldEmit(state) {
            latestState = state
            handler?(state)
        }
    }

    private func shouldEmit(_ state: MediaPlaybackState) -> Bool {
        guard state != .empty else { return latestState != .empty }
        guard state.title == latestState.title else { return true }
        guard state.isPlaying == latestState.isPlaying else { return true }
        if abs(state.duration - latestState.duration) > 0.5 { return true }
        if abs(state.elapsed - latestState.elapsed) > 0.25 { return true }
        return false
    }

    private func fetchState() async -> MediaPlaybackState {
        var spotify: MediaPlaybackState?
        var music: MediaPlaybackState?
        if ScriptedPlayer.spotify.isRunning {
            spotify = await fetch(.spotify)
        }
        if ScriptedPlayer.music.isRunning {
            music = await fetch(.music)
        }

        if let music, music.isPlaying { return music }
        if let spotify, spotify.isPlaying { return spotify }

        switch latestState.bundleIdentifier {
        case "com.apple.Music", "com.apple.iTunes":
            if let music { return music }
        case "com.spotify.client":
            if let spotify { return spotify }
        default:
            break
        }
        return .empty
    }

    private func fetch(_ player: ScriptedPlayer) async -> MediaPlaybackState? {
        let result = await executor.run(player.pollScript, cacheCompiled: true) { ScriptedTrack(descriptor: $0) }
        guard case .success(let track?) = result else { return nil }
        return track.playbackState(bundleID: player.bundleID, fallbackDuration: latestState.duration)
    }
}
