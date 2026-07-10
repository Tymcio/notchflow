import Foundation

enum MediaTimingParser {
    static func seconds(from string: String) -> Double? {
        let normalized = string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }
}
