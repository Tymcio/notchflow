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
            if let synced = json?["syncedLyrics"] as? String, !synced.isEmpty {
                return synced.components(separatedBy: "\n").first
            }
            if let plain = json?["plainLyrics"] as? String, !plain.isEmpty {
                return plain.components(separatedBy: "\n").first
            }
            return nil
        } catch {
            return nil
        }
    }
}
