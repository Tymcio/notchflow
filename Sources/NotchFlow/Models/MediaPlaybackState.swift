import Foundation

struct MediaPlaybackState: Equatable, Sendable {
    let title: String
    let artist: String
    let album: String
    let artworkURL: URL?
    let artworkData: Data?
    let isPlaying: Bool
    let elapsed: Double
    let duration: Double
    let bundleIdentifier: String?
    let lyricsSnippet: String?
    let positionSampledAt: Date

    init(
        title: String,
        artist: String,
        album: String,
        artworkURL: URL?,
        artworkData: Data?,
        isPlaying: Bool,
        elapsed: Double,
        duration: Double,
        bundleIdentifier: String?,
        lyricsSnippet: String?,
        positionSampledAt: Date = Date()
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.artworkData = artworkData
        self.isPlaying = isPlaying
        self.elapsed = elapsed
        self.duration = duration
        self.bundleIdentifier = bundleIdentifier
        self.lyricsSnippet = lyricsSnippet
        self.positionSampledAt = positionSampledAt
    }

    static let notPlayingPlaceholder = "Not Playing"

    static let empty = MediaPlaybackState(
        title: notPlayingPlaceholder,
        artist: "",
        album: "",
        artworkURL: nil,
        artworkData: nil,
        isPlaying: false,
        elapsed: 0,
        duration: 0,
        bundleIdentifier: nil,
        lyricsSnippet: nil,
        positionSampledAt: .distantPast
    )

    var trackKey: String {
        "\(title)|\(artist)|\(album)"
    }

    var hasActiveTrack: Bool {
        !title.isEmpty && title != Self.notPlayingPlaceholder
    }

    var displayTitle: String {
        hasActiveTrack ? title : loc("Not Playing")
    }

    func isSameTrack(as other: MediaPlaybackState) -> Bool {
        trackKey == other.trackKey && hasActiveTrack
    }

    func interpolatedPosition(at date: Date = Date()) -> Double {
        guard isPlaying else { return elapsed }
        let delta = date.timeIntervalSince(positionSampledAt)
        guard duration > 0 else { return elapsed + delta }
        return min(elapsed + delta, duration)
    }

    var hasUsableDuration: Bool {
        duration.isFinite && duration >= 1
    }

    /// Reject bogus sub-second values from mis-parsed notifications.
    static func isUsableTiming(_ value: Double) -> Bool {
        value.isFinite && value >= 1
    }

    /// Prefer the larger plausible timing value when merging sources.
    static func preferredTiming(incoming: Double, current: Double) -> Double {
        if isUsableTiming(incoming) { return incoming }
        if isUsableTiming(current) { return current }
        if incoming > current, incoming.isFinite { return incoming }
        if current.isFinite { return current }
        return 0
    }
}

protocol MediaSourceProviding: Sendable {
    func startMonitoring(handler: @escaping @Sendable (MediaPlaybackState) -> Void) async
    func stopMonitoring() async
    func togglePlayPause() async
    func nextTrack() async
    func previousTrack() async
    func seek(to position: Double) async
}
