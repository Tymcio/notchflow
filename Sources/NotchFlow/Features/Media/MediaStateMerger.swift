import Foundation

extension MediaPlaybackState {
    func with(artworkData: Data?) -> MediaPlaybackState {
        copy(artworkData: .some(artworkData))
    }

    func with(lyricsSnippet: String?) -> MediaPlaybackState {
        copy(lyricsSnippet: .some(lyricsSnippet))
    }

    private func copy(artworkData: Data?? = nil, lyricsSnippet: String?? = nil) -> MediaPlaybackState {
        MediaPlaybackState(
            title: title,
            artist: artist,
            album: album,
            artworkURL: artworkURL,
            artworkData: artworkData ?? self.artworkData,
            isPlaying: isPlaying,
            elapsed: elapsed,
            duration: duration,
            bundleIdentifier: bundleIdentifier,
            lyricsSnippet: lyricsSnippet ?? self.lyricsSnippet,
            positionSampledAt: positionSampledAt
        )
    }
}

/// Pure merge rules for combining media updates from the different sources.
enum MediaStateMerger {
    /// Merges a source update into the published state. Artwork and lyrics only carry over
    /// while the track stays the same, so a new track never shows the previous one's.
    static func merge(
        incoming: MediaPlaybackState,
        current: MediaPlaybackState,
        now: Date = Date()
    ) -> MediaPlaybackState {
        let sameTrack = incoming.isSameTrack(as: current)

        let elapsed = MediaPlaybackState.preferredTiming(incoming: incoming.elapsed, current: current.elapsed)
        let duration = MediaPlaybackState.preferredTiming(incoming: incoming.duration, current: current.duration)
        let timingUpdated = elapsed != current.elapsed || duration != current.duration
        let playingChanged = incoming.isPlaying != current.isPlaying

        return MediaPlaybackState(
            title: incoming.title,
            artist: incoming.artist,
            album: incoming.album,
            artworkURL: incoming.artworkURL ?? (sameTrack ? current.artworkURL : nil),
            artworkData: incoming.artworkData ?? (sameTrack ? current.artworkData : nil),
            isPlaying: incoming.isPlaying,
            elapsed: elapsed,
            duration: duration,
            bundleIdentifier: incoming.bundleIdentifier ?? current.bundleIdentifier,
            lyricsSnippet: sameTrack ? (incoming.lyricsSnippet ?? current.lyricsSnippet) : incoming.lyricsSnippet,
            positionSampledAt: (timingUpdated || playingChanged) ? now : current.positionSampledAt
        )
    }

    /// A paused update from a different player must not replace the one that is playing.
    static func isStaleOtherPlayer(_ incoming: MediaPlaybackState, current: MediaPlaybackState) -> Bool {
        guard !incoming.isPlaying,
              current.isPlaying,
              let incomingBundle = incoming.bundleIdentifier,
              let currentBundle = current.bundleIdentifier,
              incomingBundle != currentBundle else { return false }
        return !incoming.isSameTrack(as: current)
    }

    /// Folds an AppleScript poll result into the current state.
    /// Returns nil when the poll should be ignored.
    static func mergeScripting(
        _ script: MediaPlaybackState,
        into current: MediaPlaybackState,
        now: Date = Date()
    ) -> MediaPlaybackState? {
        if !script.isPlaying,
           current.isPlaying,
           let scriptBundle = script.bundleIdentifier,
           let currentBundle = current.bundleIdentifier,
           scriptBundle != currentBundle {
            return nil
        }

        let elapsed = MediaPlaybackState.preferredTiming(incoming: script.elapsed, current: current.elapsed)
        let duration = MediaPlaybackState.preferredTiming(incoming: script.duration, current: current.duration)

        if script.hasActiveTrack {
            let sameTrack = script.isSameTrack(as: current)
            return MediaPlaybackState(
                title: script.title,
                artist: script.artist,
                album: script.album,
                artworkURL: script.artworkURL ?? (sameTrack ? current.artworkURL : nil),
                artworkData: script.artworkData ?? (sameTrack ? current.artworkData : nil),
                isPlaying: script.isPlaying,
                elapsed: elapsed,
                duration: duration,
                bundleIdentifier: script.bundleIdentifier ?? current.bundleIdentifier,
                lyricsSnippet: sameTrack ? current.lyricsSnippet : nil,
                positionSampledAt: now
            )
        }

        guard MediaPlaybackState.isUsableTiming(script.elapsed)
            || MediaPlaybackState.isUsableTiming(script.duration) else {
            return current
        }
        return MediaPlaybackState(
            title: current.title,
            artist: current.artist,
            album: current.album,
            artworkURL: current.artworkURL,
            artworkData: current.artworkData,
            isPlaying: script.isPlaying,
            elapsed: elapsed,
            duration: duration,
            bundleIdentifier: current.bundleIdentifier ?? script.bundleIdentifier,
            lyricsSnippet: current.lyricsSnippet,
            positionSampledAt: now
        )
    }
}

/// Small LRU of per-track enrichment results. Misses are cached too, so a track without
/// lyrics or artwork is not looked up again on every playback update.
struct MediaEnrichmentCache<Value> {
    enum Lookup {
        case hit(Value)
        case miss
    }

    private struct Entry {
        let value: Value?
        let expiresAt: Date?
    }

    let capacity: Int
    private var entries: [String: Entry] = [:]
    /// Least recently used first.
    private var order: [String] = []

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    var count: Int { entries.count }

    /// Cached result for `key`, or nil when it must be (re)fetched.
    mutating func lookup(_ key: String, now: Date = Date()) -> Lookup? {
        guard let entry = entries[key] else { return nil }
        if let expiresAt = entry.expiresAt, now >= expiresAt {
            remove(key)
            return nil
        }
        touch(key)
        return entry.value.map(Lookup.hit) ?? .miss
    }

    /// Cached value for `key` if it is a hit.
    mutating func value(for key: String, now: Date = Date()) -> Value? {
        if case .hit(let value) = lookup(key, now: now) { return value }
        return nil
    }

    /// Stores a hit, or a miss (`value == nil`). `ttl` makes the entry expire (for transient failures).
    mutating func store(_ value: Value?, for key: String, ttl: TimeInterval? = nil, now: Date = Date()) {
        entries[key] = Entry(value: value, expiresAt: ttl.map { now.addingTimeInterval($0) })
        touch(key)
        while order.count > capacity {
            let evicted = order.removeFirst()
            entries[evicted] = nil
        }
    }

    private mutating func touch(_ key: String) {
        if let index = order.firstIndex(of: key) {
            order.remove(at: index)
        }
        order.append(key)
    }

    private mutating func remove(_ key: String) {
        entries[key] = nil
        order.removeAll { $0 == key }
    }
}
