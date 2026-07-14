import Foundation
import XCTest

final class LocalizationTests: XCTestCase {
    private let requiredLanguages = ["pl", "de", "it", "es"]

    func testStringCatalogContainsAllRequiredTranslations() throws {
        let catalogURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/NotchFlow/Resources/Localizable.xcstrings")

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: catalogURL.path),
            "Localizable.xcstrings missing at \(catalogURL.path)"
        )

        let data = try Data(contentsOf: catalogURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(json["strings"] as? [String: Any])

        var missing: [String] = []
        for (key, value) in strings {
            guard let entry = value as? [String: Any],
                  let localizations = entry["localizations"] as? [String: Any] else {
                missing.append("\(key): invalid entry")
                continue
            }

            for language in requiredLanguages {
                guard let languageEntry = localizations[language] as? [String: Any] else {
                    missing.append("\(key): missing \(language)")
                    continue
                }

                if let unit = languageEntry["stringUnit"] as? [String: Any],
                   let translation = unit["value"] as? String,
                   !translation.isEmpty {
                    continue
                }

                if let variations = languageEntry["variations"] as? [String: Any],
                   let plural = variations["plural"] as? [String: Any],
                   !plural.isEmpty {
                    continue
                }

                missing.append("\(key): empty \(language)")
            }
        }

        XCTAssertTrue(missing.isEmpty, "Missing translations:\n" + missing.joined(separator: "\n"))
    }
}
