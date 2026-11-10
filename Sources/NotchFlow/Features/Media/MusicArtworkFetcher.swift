import AppKit
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Shrinks cover art to what the island draws, so full-size album art (often 1–3 MB)
/// is neither kept in `MediaPlaybackState` nor decoded on every view update.
enum ArtworkDownsampler {
    /// Largest artwork is 52 pt in the expanded player → 2× for Retina.
    static let maxPixelSize = 104

    static func downsample(_ data: Data, maxPixelSize: Int = maxPixelSize) -> Data? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard !data.isEmpty, let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }

        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? Int,
           let height = properties[kCGImagePropertyPixelHeight] as? Int,
           max(width, height) <= maxPixelSize {
            return data
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

/// Outcome of an artwork lookup for one track.
enum ArtworkLookup: Equatable, Sendable {
    case found(Data)
    /// The track has no artwork (or it could not be fetched).
    case notFound
    /// The player had already moved on to another track; nothing is known about this one.
    case trackChanged
}

/// The track an artwork request is for. AppleScript can only ask a player for its *current*
/// track, and requests queue behind other scripts, so the answer is checked against this
/// before it is used or cached.
struct ArtworkTrackIdentity: Sendable {
    let key: String
    let title: String
    let artist: String

    /// True when the player's current track (as reported alongside the artwork) is this one.
    /// Case and surrounding whitespace are ignored; an empty artist on either side matches.
    func matches(playerTitle: String, playerArtist: String) -> Bool {
        func normalized(_ value: String) -> String {
            value.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
        }
        guard normalized(playerTitle) == normalized(title) else { return false }
        let expectedArtist = normalized(artist)
        let reportedArtist = normalized(playerArtist)
        return expectedArtist.isEmpty || reportedArtist.isEmpty || expectedArtist == reportedArtist
    }
}

enum MusicArtworkFetcher {
    private static let cacheDirectory: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("notchflow-artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let maxCacheBytes = 10 * 1024 * 1024
    private static let maxCacheFiles = 200
    private static let legacyCacheEntryBytes = 96 * 1024

    private static let allowedArtworkHosts: Set<String> = [
        "i.scdn.co",
        "mosaic.scdn.co",
        "image-cdn-ak.spotifycdn.com",
        "image-cdn-fa.spotifycdn.com",
        "thisis-images.spotifycdn.com",
        "wrapped-images.spotifycdn.com"
    ]

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 10
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    private actor InFlightRequests {
        private var tasks: [String: Task<ArtworkLookup, Never>] = [:]

        func data(for key: String, fetch: @escaping @Sendable () async -> ArtworkLookup) async -> ArtworkLookup {
            if let existing = tasks[key] {
                return await existing.value
            }

            let task = Task { await fetch() }
            tasks[key] = task
            defer { tasks[key] = nil }
            return await task.value
        }
    }

    private static let inFlight = InFlightRequests()

    /// Downsampled artwork for `track`: notification bytes, artwork URL, or asking the player.
    /// Never runs on the main actor's executor.
    static func artwork(
        rawData: Data?,
        artworkURL: URL?,
        bundleID: String?,
        track: ArtworkTrackIdentity
    ) async -> ArtworkLookup {
        if let rawData, let small = ArtworkDownsampler.downsample(rawData) {
            return .found(small)
        }
        if let artworkURL, let data = await fetchFromURL(artworkURL),
           let small = ArtworkDownsampler.downsample(data) {
            return .found(small)
        }
        return await fetch(bundleID: bundleID, track: track)
    }

    static func fetch(bundleID: String?, track: ArtworkTrackIdentity, forceRefresh: Bool = false) async -> ArtworkLookup {
        guard let bundleID else { return .notFound }
        let key = cacheKey(for: track.key)
        let cacheURL = cacheDirectory.appendingPathComponent("\(key).jpg")

        if !forceRefresh, let cached = try? Data(contentsOf: cacheURL), !cached.isEmpty {
            // Entries written by older builds hold full-size art — shrink them once.
            guard cached.count > legacyCacheEntryBytes else { return .found(cached) }
            guard let small = ArtworkDownsampler.downsample(cached) else { return .notFound }
            try? small.write(to: cacheURL, options: .atomic)
            return .found(small)
        }

        let result = await inFlight.data(for: key) {
            let reply: PlayerArtworkReply?
            switch bundleID {
            case "com.apple.Music", "com.apple.iTunes":
                reply = await fetchFromMusicApp()
            case "com.spotify.client":
                reply = await fetchFromSpotifyApp()
            default:
                reply = nil
            }
            guard let reply else { return .notFound }
            // The script queue may have run after a track skip: never take another track's art.
            guard track.matches(playerTitle: reply.title, playerArtist: reply.artist) else {
                return .trackChanged
            }
            guard let raw = reply.artwork, let data = ArtworkDownsampler.downsample(raw) else { return .notFound }
            return .found(data)
        }

        if case .found(let data) = result, !Task.isCancelled {
            try? data.write(to: cacheURL, options: .atomic)
            trimCacheIfNeeded()
        }
        return result
    }

    /// What a player reported for its current track.
    private struct PlayerArtworkReply: Sendable {
        let title: String
        let artist: String
        let artwork: Data?
    }

    /// Splits a `{name, artist, payload}` AppleScript list.
    private struct ScriptTrackReply: Sendable {
        let title: String
        let artist: String
        let payload: String

        init?(_ descriptor: NSAppleEventDescriptor) {
            guard descriptor.numberOfItems >= 3,
                  let title = descriptor.atIndex(1)?.stringValue else { return nil }
            self.title = title
            self.artist = descriptor.atIndex(2)?.stringValue ?? ""
            self.payload = descriptor.atIndex(3)?.stringValue ?? ""
        }
    }

    static func fetchFromURL(_ url: URL) async -> Data? {
        if url.isFileURL {
            return try? Data(contentsOf: url)
        }
        guard url.scheme?.hasPrefix("http") == true, isAllowedArtworkHost(url) else {
            return nil
        }
        return await httpData(from: url)
    }

    private static func cacheKey(for trackKey: String) -> String {
        let digest = SHA256.hash(data: Data(trackKey.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Music can only hand artwork over as a file; it is read and deleted straight away.
    /// The script reports which track the artwork belongs to.
    private static func fetchFromMusicApp() async -> PlayerArtworkReply? {
        let fileName = "notchflow-cover-\(UUID().uuidString)"
        let script = """
        with timeout of 5 seconds
            tell application "Music"
                try
                    if player state is not stopped then
                        set t to current track
                        set trackName to name of t
                        set trackArtist to artist of t
                        if (count of artworks of t) > 0 then
                            set artData to data of artwork 1 of t
                            set f to (POSIX path of (path to temporary items)) & "\(fileName)"
                            set fileRef to open for access POSIX file f with write permission
                            set eof of fileRef to 0
                            write artData to fileRef
                            close access fileRef
                            return {trackName, trackArtist, f}
                        end if
                        return {trackName, trackArtist, ""}
                    end if
                end try
            end tell
        end timeout
        """
        guard case .success(let reply?) = await AppleScriptExecutor.shared.run(
            script,
            transform: { ScriptTrackReply($0) }
        ) else { return nil }
        guard !reply.payload.isEmpty else {
            return PlayerArtworkReply(title: reply.title, artist: reply.artist, artwork: nil)
        }
        let url = URL(fileURLWithPath: reply.payload)
        defer { try? FileManager.default.removeItem(at: url) }
        return PlayerArtworkReply(title: reply.title, artist: reply.artist, artwork: try? Data(contentsOf: url))
    }

    private static func fetchFromSpotifyApp() async -> PlayerArtworkReply? {
        let script = """
        with timeout of 5 seconds
            tell application "Spotify"
                try
                    if player state is not stopped then
                        set t to current track
                        return {name of t, artist of t, artwork url of t}
                    end if
                end try
            end tell
        end timeout
        """
        guard case .success(let reply?) = await AppleScriptExecutor.shared.run(
            script,
            cacheCompiled: true,
            transform: { ScriptTrackReply($0) }
        ) else { return nil }
        let artwork: Data?
        if let url = URL(string: reply.payload), !reply.payload.isEmpty {
            artwork = await fetchFromURL(url)
        } else {
            artwork = nil
        }
        return PlayerArtworkReply(title: reply.title, artist: reply.artist, artwork: artwork)
    }

    private static func httpData(from url: URL) async -> Data? {
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return data
        } catch {
            NotchFlowLog.media.debug("Artwork download failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func isAllowedArtworkHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return allowedArtworkHosts.contains(host)
    }

    private static func trimCacheIfNeeded() {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var entries: [(url: URL, size: Int, date: Date)] = []
        var totalSize = 0

        for url in files {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = values?.fileSize ?? 0
            let date = values?.contentModificationDate ?? .distantPast
            entries.append((url, size, date))
            totalSize += size
        }

        guard entries.count > maxCacheFiles || totalSize > maxCacheBytes else { return }

        entries.sort { $0.date < $1.date }
        var remaining = entries.count
        for entry in entries {
            guard remaining > maxCacheFiles || totalSize > maxCacheBytes else { break }
            if (try? fileManager.removeItem(at: entry.url)) != nil {
                remaining -= 1
                totalSize -= entry.size
            }
        }
    }
}
