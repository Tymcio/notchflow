import Foundation

/// Outcome of a lyrics lookup — misses are cached by the caller, failures retried later.
enum LyricsLookup: Equatable, Sendable {
    case found(String)
    /// lrclib.net answered but has no lyrics for this track.
    case notFound
    /// Network error, timeout or unexpected response.
    case failed
}

struct LyricsService: Sendable {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 8
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    func lookup(title: String, artist: String) async -> LyricsLookup {
        guard !title.isEmpty else { return .notFound }
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist)
        ]
        guard let url = components.url else { return .notFound }

        do {
            let (data, response) = try await Self.session.data(from: url)
            guard let http = response as? HTTPURLResponse else { return .failed }
            if http.statusCode == 404 { return .notFound }
            guard (200..<300).contains(http.statusCode) else { return .failed }
            return Self.parse(data)
        } catch {
            if (error as? URLError)?.code != .cancelled {
                NotchFlowLog.media.debug("Lyrics lookup failed: \(error.localizedDescription, privacy: .public)")
            }
            return .failed
        }
    }

    /// Extracts the first lyric line from an lrclib.net `/api/get` response.
    static func parse(_ data: Data) -> LyricsLookup {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .failed
        }
        if let synced = json["syncedLyrics"] as? String, let line = firstLyricLine(synced) {
            return .found(line)
        }
        if let plain = json["plainLyrics"] as? String, let line = firstLyricLine(plain) {
            return .found(line)
        }
        return .notFound
    }

    /// Returns the first non-empty lyric line with LRC tags like `[00:14.74]` or `[ar:…]` removed.
    static func firstLyricLine(_ raw: String) -> String? {
        for line in raw.components(separatedBy: "\n") {
            let stripped = line
                .replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            if !stripped.isEmpty {
                return stripped
            }
        }
        return nil
    }
}
