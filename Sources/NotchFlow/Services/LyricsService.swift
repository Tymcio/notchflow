import Foundation

struct LyricsService {
    func fetchSnippet(title: String, artist: String) async -> String? {
        guard !title.isEmpty else { return nil }
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist)
        ]
        guard let url = components.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let synced = json?["syncedLyrics"] as? String, let line = firstLyricLine(synced) {
                return line
            }
            if let plain = json?["plainLyrics"] as? String, let line = firstLyricLine(plain) {
                return line
            }
            return nil
        } catch {
            return nil
        }
    }

    /// Returns the first non-empty lyric line with LRC tags like `[00:14.74]` or `[ar:…]` removed.
    private func firstLyricLine(_ raw: String) -> String? {
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
