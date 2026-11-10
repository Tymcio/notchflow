import XCTest
@testable import NotchFlow

/// Packaged apps only contain the `.lproj` tables SwiftPM compiles from the String Catalog,
/// never the `.xcstrings` file itself. Translations must still resolve from them.
final class CompiledLocalizationTests: XCTestCase {
    private func compiledTable(_ language: String) throws -> Bundle {
        let path = try XCTUnwrap(
            ResourceBundle.bundle.path(forResource: language, ofType: "lproj"),
            "resource bundle has no \(language).lproj"
        )
        return try XCTUnwrap(Bundle(path: path))
    }

    func testResolvesFromCompiledTablesWithoutTheRawCatalog() throws {
        let polish = L10nCatalog.localized("Resets in %@", languageCode: "pl", catalog: [:], compiled: try compiledTable("pl"))
        XCTAssertEqual(polish, "Odświeżenie za %@")
        let german = L10nCatalog.localized("Resets in %@", languageCode: "de", catalog: [:], compiled: try compiledTable("de"))
        XCTAssertEqual(german, "Aktualisierung in %@")
    }

    func testFallsBackToTheEnglishKey() throws {
        let missing = L10nCatalog.localized("No such key 42", languageCode: "pl", catalog: [:], compiled: try compiledTable("pl"))
        XCTAssertEqual(missing, "No such key 42")
        XCTAssertEqual(L10nCatalog.localized("Resets in %@", languageCode: "en", catalog: [:], compiled: nil), "Resets in %@")
    }
}
