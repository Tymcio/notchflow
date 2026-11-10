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
        private var tasks: [String: Task<Data?, Never>] = [:]

        func data(for key: String, fetch: @escaping @Sendable () async -> Data?) async -> Data? {
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

    /// Downsampled artwork for the current track: notification bytes, artwork URL, or
    /// asking the player. Never runs on the main actor's executor.
    static func artwork(
        rawData: Data?,
        artworkURL: URL?,
        bundleID: String?,
        trackKey: String
    ) async -> Data? {
        if let rawData, let small = ArtworkDownsampler.downsample(rawData) {
            return small
        }
        if let artworkURL, let data = await fetchFromURL(artworkURL),
           let small = ArtworkDownsampler.downsample(data) {
            return small
        }
        return await fetch(bundleID: bundleID, trackKey: trackKey)
    }

    static func fetch(bundleID: String?, trackKey: String, forceRefresh: Bool = false) async -> Data? {
        guard let bundleID else { return nil }
        let key = cacheKey(for: trackKey)
        let cacheURL = cacheDirectory.appendingPathComponent("\(key).jpg")

        if !forceRefresh, let cached = try? Data(contentsOf: cacheURL), !cached.isEmpty {
            // Entries written by older builds hold full-size art — shrink them once.
            guard cached.count > legacyCacheEntryBytes else { return cached }
            guard let small = ArtworkDownsampler.downsample(cached) else { return nil }
            try? small.write(to: cacheURL, options: .atomic)
            return small
        }

        return await inFlight.data(for: key) {
            let raw: Data?
            switch bundleID {
            case "com.apple.Music", "com.apple.iTunes":
                raw = await fetchFromMusicApp()
            case "com.spotify.client":
                raw = await fetchFromSpotifyApp()
            default:
                raw = nil
            }

            guard let raw, let data = ArtworkDownsampler.downsample(raw) else { return nil }
            try? data.write(to: cacheURL, options: .atomic)
            trimCacheIfNeeded()
            return data
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
    private static func fetchFromMusicApp() async -> Data? {
        let fileName = "notchflow-cover-\(UUID().uuidString)"
        let script = """
        with timeout of 5 seconds
            tell application "Music"
                try
                    if player state is not stopped then
                        if (count of artworks of current track) > 0 then
                            set artData to data of artwork 1 of current track
                            set f to (POSIX path of (path to temporary items)) & "\(fileName)"
                            set fileRef to open for access POSIX file f with write permission
                            set eof of fileRef to 0
                            write artData to fileRef
                            close access fileRef
                            return f
                        end if
                    end if
                end try
            end tell
        end timeout
        """
        guard case .success(let path?) = await AppleScriptExecutor.shared.run(script, transform: { $0.stringValue }),
              !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        defer { try? FileManager.default.removeItem(at: url) }
        return try? Data(contentsOf: url)
    }

    private static func fetchFromSpotifyApp() async -> Data? {
        let script = """
        with timeout of 5 seconds
            tell application "Spotify"
                try
                    if player state is not stopped then
                        return artwork url of current track
                    end if
                end try
            end tell
        end timeout
        """
        guard case .success(let urlString?) = await AppleScriptExecutor.shared.run(
            script,
            cacheCompiled: true,
            transform: { $0.stringValue }
        ), let url = URL(string: urlString) else { return nil }
        return await fetchFromURL(url)
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
