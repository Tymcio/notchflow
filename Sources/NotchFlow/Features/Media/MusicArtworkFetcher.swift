import AppKit
import CryptoKit
import Foundation

enum MusicArtworkFetcher {
    private static let cacheDirectory: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("notchflow-artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let maxCacheBytes = 50 * 1024 * 1024
    private static let maxCacheFiles = 200

    private static let allowedArtworkHosts: Set<String> = [
        "i.scdn.co",
        "mosaic.scdn.co",
        "image-cdn-ak.spotifycdn.com",
        "image-cdn-fa.spotifycdn.com",
        "thisis-images.spotifycdn.com",
        "wrapped-images.spotifycdn.com"
    ]

    private actor InFlightRequests {
        private var tasks: [String: Task<Data?, Never>] = [:]

        func data(for key: String, fetch: @escaping () async -> Data?) async -> Data? {
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

    static func fetch(bundleID: String?, trackKey: String, forceRefresh: Bool = false) async -> Data? {
        guard let bundleID else { return nil }
        let key = cacheKey(for: trackKey)
        let cacheURL = cacheDirectory.appendingPathComponent("\(key).jpg")

        if !forceRefresh, let cached = try? Data(contentsOf: cacheURL), !cached.isEmpty {
            return cached
        }

        return await inFlight.data(for: key) {
            let data: Data?
            switch bundleID {
            case "com.apple.Music", "com.apple.iTunes":
                data = await fetchFromMusicApp(trackKey: trackKey)
            case "com.spotify.client":
                data = await fetchFromSpotifyApp()
            default:
                data = nil
            }

            if let data, !data.isEmpty {
                try? data.write(to: cacheURL, options: .atomic)
                await trimCacheIfNeeded()
            }
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

    /// Synchronous read from disk cache only — safe for hot paths that already have artwork on disk.
    static func cachedData(trackKey: String) -> Data? {
        let cacheURL = cacheDirectory.appendingPathComponent("\(cacheKey(for: trackKey)).jpg")
        guard let data = try? Data(contentsOf: cacheURL), !data.isEmpty else { return nil }
        return data
    }

    private static func cacheKey(for trackKey: String) -> String {
        let digest = SHA256.hash(data: Data(trackKey.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func fetchFromMusicApp(trackKey: String) async -> Data? {
        let fileName = "notchflow-cover-\(cacheKey(for: trackKey))"
        let script = """
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
        """
        return readExportedFile(runAppleScript(script))
    }

    private static func fetchFromSpotifyApp() async -> Data? {
        let script = """
        tell application "Spotify"
            try
                if player state is not stopped then
                    set artURL to artwork url of current track
                    return artURL
                end if
            end try
        end tell
        """
        guard let urlString = runAppleScript(script), let url = URL(string: urlString) else { return nil }
        return await fetchFromURL(url)
    }

    private static func readExportedFile(_ path: String?) -> Data? {
        guard let path, !path.isEmpty else { return nil }
        return try? Data(contentsOf: URL(fileURLWithPath: path))
    }

    private static func runAppleScript(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        return script.executeAndReturnError(&error).stringValue
    }

    private static func httpData(from url: URL) async -> Data? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    private static func isAllowedArtworkHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return allowedArtworkHosts.contains(host)
    }

    private static func trimCacheIfNeeded() async {
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
        for entry in entries {
            guard entries.count > maxCacheFiles || totalSize > maxCacheBytes else { break }
            if (try? fileManager.removeItem(at: entry.url)) != nil {
                entries.removeAll { $0.url == entry.url }
                totalSize -= entry.size
            }
        }
    }
}
