import Foundation

enum MediaTimingParser {
    /// Parses a player timing string that may use the user's locale ("12,5", "1.234,5", "1 234,5").
    static func seconds(from string: String) -> Double? {
        var normalized = string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { $0 != " " && $0 != "\u{00A0}" && $0 != "\u{202F}" }
        if let lastComma = normalized.lastIndex(of: ","), let lastDot = normalized.lastIndex(of: ".") {
            // Both present: the later one is the decimal separator, the other groups thousands.
            let grouping: Character = lastComma > lastDot ? "." : ","
            normalized.removeAll { $0 == grouping }
        }
        normalized = normalized.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite else { return nil }
        return value
    }
}
