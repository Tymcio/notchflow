import XCTest
@testable import NotchFlow

/// Depending on the toolchain, SwiftPM either copies `Localizable.xcstrings` into the resource
/// bundle or compiles it into `<lang>.lproj/Localizable.strings` (newer Xcode). Translations
/// must resolve from whichever one the packaged app contains.
final class CompiledLocalizationTests: XCTestCase {
    private func compiledTable(_ language: String) -> Bundle? {
        ResourceBundle.bundle.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
    }

    private var hasRawCatalog: Bool {
        ResourceBundle.bundle.url(forResource: "Localizable", withExtension: "xcstrings") != nil
    }

    func testThePackagedBundleCarriesTranslationsInOneOfTheTwoForms() {
        XCTAssertTrue(
            hasRawCatalog || compiledTable("pl") != nil,
            "resource bundle has neither Localizable.xcstrings nor pl.lproj"
        )
    }

    func testResolvesFromCompiledTablesWithoutTheRawCatalog() throws {
        guard let polish = compiledTable("pl"), let german = compiledTable("de") else {
            throw XCTSkip("this toolchain copies the raw String Catalog instead of compiling .lproj tables")
        }
        XCTAssertEqual(
            L10nCatalog.localized("Resets in %@", languageCode: "pl", catalog: [:], compiled: polish),
            "Odświeżenie za %@"
        )
        XCTAssertEqual(
            L10nCatalog.localized("Resets in %@", languageCode: "de", catalog: [:], compiled: german),
            "Aktualisierung in %@"
        )
        XCTAssertEqual(
            L10nCatalog.localized("No such key 42", languageCode: "pl", catalog: [:], compiled: polish),
            "No such key 42"
        )
    }

    func testRawCatalogWinsAndEnglishUsesTheKey() {
        let catalog = ["Resets in %@": ["pl": "Odświeżenie za %@"]]
        XCTAssertEqual(
            L10nCatalog.localized("Resets in %@", languageCode: "pl", catalog: catalog, compiled: nil),
            "Odświeżenie za %@"
        )
        XCTAssertEqual(
            L10nCatalog.localized("Missing", languageCode: "pl", catalog: catalog, compiled: nil),
            "Missing"
        )
        XCTAssertEqual(
            L10nCatalog.localized("Resets in %@", languageCode: "en", catalog: catalog, compiled: nil),
            "Resets in %@"
        )
    }
}
