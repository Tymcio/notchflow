import AppKit
import Foundation

/// AppleScript-backed media source for Spotify and Apple Music.
/// Polls only when explicitly enabled — otherwise relies on distributed notifications.
final class ScriptingBridgeMediaSource: MediaSourceProviding, @unchecked Sendable {
    private var handler: (@Sendable (MediaPlaybackState) -> Void)?
    private var pollTask: Task<Void, Never>?
    private var latestState = MediaPlaybackState.empty
    private let pollingCoordinator = PollingCoordinator()

    func startMonitoring(handler: @escaping @Sendable (MediaPlaybackState) -> Void) async {
        self.handler = handler
        await setPollingActive(false)
        let initial = await fetchState()
        latestState = initial
        if initial != .empty {
            handler(initial)
        }
    }

    func stopMonitoring() async {
        await setPollingActive(false)
        handler = nil
    }

    func setPollingActive(_ active: Bool) async {
        let changed = await pollingCoordinator.setActive(active)
        guard changed else { return }

        pollTask?.cancel()
        pollTask = nil

        guard active, let handler else { return }

        pollTask = Task {
            while !Task.isCancelled {
                guard await pollingCoordinator.isActive else { break }

                let state = await fetchState()
                if shouldEmit(state) {
                    latestState = state
                    handler(state)
                }
                try? await Task.sleep(for: .seconds(0.75))
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

    private func shouldEmit(_ state: MediaPlaybackState) -> Bool {
        guard state != .empty else { return latestState != .empty }
        guard state.title == latestState.title else { return true }
        guard state.isPlaying == latestState.isPlaying else { return true }
        if abs(state.duration - latestState.duration) > 0.5 { return true }
        if abs(state.elapsed - latestState.elapsed) > 0.25 { return true }
        return false
    }

    private func fetchState() async -> MediaPlaybackState {
        let spotify = fetchSpotifyState()
        let music = fetchMusicState()

        if music?.isPlaying == true { return music! }
        if spotify?.isPlaying == true { return spotify! }

        if let bundleID = latestState.bundleIdentifier {
            switch bundleID {
            case "com.apple.Music", "com.apple.iTunes":
                if let music { return music }
            case "com.spotify.client":
                if let spotify { return spotify }
            default:
                break
            }
        }

        return .empty
    }

    private func fetchSpotifyState() -> MediaPlaybackState? {
        let script = """
        if application "Spotify" is running then
            tell application "Spotify"
                if player state is playing or player state is paused then
                    return name of current track & "|||" & artist of current track & "|||" & album of current track & "|||" & (player state as string) & "|||" & (duration of current track as string) & "|||" & (player position as string)
                end if
            end tell
        end if
        return ""
        """
        return parseScriptResult(script, bundleID: "com.spotify.client")
    }

    private func fetchMusicState() -> MediaPlaybackState? {
        let script = """
        if application "Music" is running then
            tell application "Music"
                if player state is playing or player state is paused then
                    return name of current track & "|||" & artist of current track & "|||" & album of current track & "|||" & (player state as string) & "|||" & (duration of current track as string) & "|||" & (player position as string)
                end if
            end tell
        end if
        return ""
        """
        return parseScriptResult(script, bundleID: "com.apple.Music")
    }

    private func parseScriptResult(_ script: String, bundleID: String) -> MediaPlaybackState? {
        guard let output = runAppleScript(script), !output.isEmpty else { return nil }
        let parts = output.components(separatedBy: "|||")
        guard parts.count >= 6 else { return nil }

        let isPlaying = parts[3].lowercased() == "playing"
        let rawDuration = MediaTimingParser.seconds(from: parts[4]) ?? 0
        let duration = bundleID == "com.spotify.client" ? rawDuration / 1000.0 : rawDuration
        let elapsed = MediaTimingParser.seconds(from: parts[5]) ?? 0
        let resolvedDuration = duration > 0 ? duration : latestState.duration

        return MediaPlaybackState(
            title: parts[0],
            artist: parts[1],
            album: parts[2],
            artworkURL: nil,
            artworkData: nil,
            isPlaying: isPlaying,
            elapsed: max(0, elapsed),
            duration: max(0, resolvedDuration),
            bundleIdentifier: bundleID,
            lyricsSnippet: nil,
            positionSampledAt: Date()
        )
    }

    private func runAppleScript(_ source: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        if let data = source.data(using: .utf8) {
            stdin.fileHandleForWriting.write(data)
        }
        stdin.fileHandleForWriting.closeFile()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        guard var raw = String(data: outData, encoding: .utf8) else { return nil }
        if raw.hasSuffix("\n") {
            raw.removeLast()
        }
        return raw.isEmpty ? nil : raw
    }
}

private actor PollingCoordinator {
    private(set) var isActive = false

    func setActive(_ active: Bool) -> Bool {
        let changed = isActive != active
        isActive = active
        return changed
    }
}
