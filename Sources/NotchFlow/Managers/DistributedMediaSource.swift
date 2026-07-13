import AppKit
import Foundation

/// Event-driven media source using NSDistributedNotificationCenter (Music, Spotify, iTunes).
final class DistributedMediaSource: MediaSourceProviding, @unchecked Sendable {
    private let center = DistributedNotificationCenter.default()
    private var observers: [NSObjectProtocol] = []
    private var handler: (@Sendable (MediaPlaybackState) -> Void)?
    private var latestState = MediaPlaybackState.empty

    func startMonitoring(handler: @escaping @Sendable (MediaPlaybackState) -> Void) async {
        self.handler = handler
        registerObservers()
        emitCurrentState()
    }

    func stopMonitoring() async {
        observers.forEach { center.removeObserver($0) }
        observers = []
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

    private func registerObservers() {
        observers.forEach { center.removeObserver($0) }
        observers = []

        let names = [
            "com.apple.Music.playerInfo",
            "com.spotify.client.PlaybackStateChanged",
            "com.apple.iTunes.playerInfo"
        ]

        for name in names {
            let token = center.addObserver(forName: NSNotification.Name(name), object: nil, queue: .main) { [weak self] notification in
                self?.handle(notification: notification)
            }
            observers.append(token)
        }
    }

    private func handle(notification: Notification) {
        let info = notification.userInfo ?? [:]
        let sourceBundleID = bundleIdentifier(for: notification.name.rawValue)

        let playerState = firstString(in: info, keys: ["Player State", "State"])?.lowercased()
        if playerState == "stopped" {
            if let sourceBundleID,
               latestState.bundleIdentifier == nil || latestState.bundleIdentifier == sourceBundleID {
                latestState = .empty
                handler?(latestState)
            }
            return
        }

        let title = firstString(in: info, keys: ["Title", "Name"]) ?? latestState.title
        let artist = firstString(in: info, keys: ["Artist", "Album Artist"]) ?? latestState.artist
        let album = firstString(in: info, keys: ["Album"]) ?? latestState.album
        let artworkString = firstString(in: info, keys: ["Album Art URL", "Artwork URL"])
        let artworkURL = artworkString.flatMap { URL(string: $0) } ?? latestState.artworkURL

        let playbackRate = doubleValue(info["Playback Rate"]) ?? 0
        let bundleID = firstString(in: info, keys: ["Player Bundle Identifier"]) ?? sourceBundleID ?? latestState.bundleIdentifier

        let timing = parseTiming(from: info, bundleID: bundleID, previous: latestState)
        let isPlaying = playbackRate > 0 || playerState == "playing"

        if !isPlaying,
           latestState.isPlaying,
           let sourceBundleID,
           sourceBundleID != latestState.bundleIdentifier {
            return
        }

        if !isPlaying, playerState == "paused" || playbackRate == 0 {
            latestState = MediaPlaybackState(
                title: title.isEmpty ? latestState.title : title,
                artist: artist,
                album: album,
                artworkURL: artworkURL,
                artworkData: latestState.artworkData,
                isPlaying: false,
                elapsed: timing.elapsed,
                duration: timing.duration,
                bundleIdentifier: bundleID,
                lyricsSnippet: latestState.lyricsSnippet
            )
            handler?(latestState)
            return
        }

        let artworkDataFromNotification = parseArtworkDataSync(from: info)
        if let artworkDataFromNotification {
            applyState(
                title: title,
                artist: artist,
                album: album,
                artworkURL: artworkURL,
                artworkData: artworkDataFromNotification,
                isPlaying: isPlaying,
                timing: timing,
                bundleID: bundleID
            )
            return
        }

        if let artworkURL, artworkURL.isFileURL {
            let expectedBundleID = bundleID
            let capturedTitle = title
            let capturedArtist = artist
            let capturedAlbum = album
            let capturedIsPlaying = isPlaying
            let capturedTiming = timing
            Task.detached(priority: .utility) { [weak self] in
                let data = try? Data(contentsOf: artworkURL)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.applyState(
                        title: capturedTitle,
                        artist: capturedArtist,
                        album: capturedAlbum,
                        artworkURL: artworkURL,
                        artworkData: data ?? self.latestState.artworkData,
                        isPlaying: capturedIsPlaying,
                        timing: capturedTiming,
                        bundleID: expectedBundleID
                    )
                }
            }
            return
        }

        applyState(
            title: title,
            artist: artist,
            album: album,
            artworkURL: artworkURL,
            artworkData: latestState.artworkData,
            isPlaying: isPlaying,
            timing: timing,
            bundleID: bundleID
        )
    }

    private func applyState(
        title: String,
        artist: String,
        album: String,
        artworkURL: URL?,
        artworkData: Data?,
        isPlaying: Bool,
        timing: (elapsed: Double, duration: Double),
        bundleID: String?
    ) {
        latestState = MediaPlaybackState(
            title: title.isEmpty ? "Not Playing" : title,
            artist: artist,
            album: album,
            artworkURL: artworkURL,
            artworkData: artworkData,
            isPlaying: isPlaying,
            elapsed: timing.elapsed,
            duration: timing.duration,
            bundleIdentifier: bundleID,
            lyricsSnippet: latestState.lyricsSnippet
        )

        handler?(latestState)
    }

    private func parseTiming(
        from info: [AnyHashable: Any],
        bundleID: String?,
        previous: MediaPlaybackState
    ) -> (elapsed: Double, duration: Double) {
        switch bundleID {
        case "com.spotify.client":
            let durationMs = firstNumber(in: info, keys: ["Playback Duration", "Duration"])
            let positionMs = firstNumber(in: info, keys: ["Playback Position", "Position", "Playback Progress"])
            let duration = (durationMs ?? (previous.duration * 1000)) / 1000.0
            let elapsed = (positionMs ?? (previous.elapsed * 1000)) / 1000.0
            return (max(0, elapsed), max(0, duration))

        case "com.apple.Music", "com.apple.iTunes":
            let durationMicros = firstNumber(in: info, keys: ["Total Time", "Duration"])
            let elapsedMicros = firstNumber(in: info, keys: ["Elapsed Time", "Playback Progress"])
            let duration = (durationMicros ?? (previous.duration * 1_000_000)) / 1_000_000.0
            let elapsed = (elapsedMicros ?? (previous.elapsed * 1_000_000)) / 1_000_000.0
            return (max(0, elapsed), max(0, duration))

        default:
            if let durationMs = firstNumber(in: info, keys: ["Playback Duration"]) {
                let positionMs = firstNumber(in: info, keys: ["Playback Position", "Position"])
                let duration = durationMs / 1000.0
                let elapsed = (positionMs ?? (previous.elapsed * 1000)) / 1000.0
                return (max(0, elapsed), max(0, duration))
            }

            let durationMicros = firstNumber(in: info, keys: ["Total Time"])
            let elapsedMicros = firstNumber(in: info, keys: ["Elapsed Time"])
            let duration = (durationMicros ?? (previous.duration * 1_000_000)) / 1_000_000.0
            let elapsed = (elapsedMicros ?? (previous.elapsed * 1_000_000)) / 1_000_000.0
            return (max(0, elapsed), max(0, duration))
        }
    }

    private func emitCurrentState() {
        handler?(latestState)
    }

    private func parseArtworkDataSync(from info: [AnyHashable: Any]) -> Data? {
        if let data = info["Artwork"] as? Data {
            return data
        }
        if let data = info["Artwork"] as? NSData {
            return data as Data
        }
        return nil
    }

    private func firstString(in info: [AnyHashable: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = info[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func firstNumber(in info: [AnyHashable: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = doubleValue(info[key]) {
                return value
            }
        }
        return nil
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = value as? String {
            return MediaTimingParser.seconds(from: string)
        }
        return nil
    }

    private func bundleIdentifier(for notificationName: String) -> String? {
        switch notificationName {
        case "com.spotify.client.PlaybackStateChanged":
            return "com.spotify.client"
        case "com.apple.Music.playerInfo":
            return "com.apple.Music"
        case "com.apple.iTunes.playerInfo":
            return "com.apple.iTunes"
        default:
            return nil
        }
    }
}
