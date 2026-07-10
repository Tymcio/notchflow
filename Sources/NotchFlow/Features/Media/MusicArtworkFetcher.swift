import AppKit
import Foundation

enum MusicArtworkFetcher {
    private static let cacheDirectory: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("notchflow-artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func fetch(bundleID: String?, trackKey: String, forceRefresh: Bool = false) -> Data? {
        guard let bundleID else { return nil }
        let cacheURL = cacheDirectory.appendingPathComponent(cacheKey(for: trackKey))

        if !forceRefresh, let cached = try? Data(contentsOf: cacheURL), !cached.isEmpty {
            return cached
        }

        let data: Data?
        switch bundleID {
        case "com.apple.Music", "com.apple.iTunes":
            data = fetchFromMusicApp(trackKey: trackKey)
        case "com.spotify.client":
            data = fetchFromSpotifyApp()
        default:
            data = nil
        }

        if let data, !data.isEmpty {
            try? data.write(to: cacheURL, options: .atomic)
        }
        return data
    }

    static func fetchFromURL(_ url: URL) -> Data? {
        if url.isFileURL {
            return try? Data(contentsOf: url)
        }
        if url.scheme?.hasPrefix("http") == true {
            return syncHTTPData(from: url)
        }
        return nil
    }

    private static func cacheKey(for trackKey: String) -> String {
        let hash = trackKey.hashValue.magnitude
        return "cover-\(hash).jpg"
    }

    private static func fetchFromMusicApp(trackKey: String) -> Data? {
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

    private static func fetchFromSpotifyApp() -> Data? {
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
        return syncHTTPData(from: url)
    }

    private static func readExportedFile(_ path: String?) -> Data? {
        guard let path, !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        return try? Data(contentsOf: url)
    }

    private static func runAppleScript(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        return script.executeAndReturnError(&error).stringValue
    }

    private static func syncHTTPData(from url: URL) -> Data? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Data?
        URLSession.shared.dataTask(with: url) { data, _, _ in
            result = data
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 4)
        return result
    }
}
