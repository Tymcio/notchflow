import Foundation
import SwiftUI

enum LanguageResolver {
    private static let supported = Set(["en", "pl", "de", "it", "es"])

    /// Active UI language: per-app override, then first supported system language, else English.
    static var languageCode: String {
        if let override = appLanguageOverride, supported.contains(override) {
            return override
        }
        for language in Locale.preferredLanguages {
            let code = String(language.prefix(2))
            if supported.contains(code) {
                return code
            }
        }
        return "en"
    }

    private static var appLanguageOverride: String? {
        guard let bundleID = Bundle.main.bundleIdentifier,
              let domain = UserDefaults.standard.persistentDomain(forName: bundleID),
              let languages = domain["AppleLanguages"] as? [String],
              let first = languages.first else {
            return nil
        }
        return String(first.prefix(2))
    }
}

private enum L10nCatalog {
    static let languageCode = LanguageResolver.languageCode

    private static let translations: [String: [String: String]] = {
        guard let url = Bundle.module.url(forResource: "Localizable", withExtension: "xcstrings"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = root["strings"] as? [String: Any] else {
            return [:]
        }

        var table: [String: [String: String]] = [:]
        table.reserveCapacity(strings.count)

        for (key, value) in strings {
            guard let entry = value as? [String: Any],
                  let localizations = entry["localizations"] as? [String: Any] else {
                continue
            }

            var byLanguage: [String: String] = [:]
            for (language, localization) in localizations {
                guard let localizationEntry = localization as? [String: Any] else { continue }
                if let unit = localizationEntry["stringUnit"] as? [String: Any],
                   let text = unit["value"] as? String,
                   !text.isEmpty {
                    byLanguage[language] = text
                }
            }

            if !byLanguage.isEmpty {
                table[key] = byLanguage
            }
        }

        return table
    }()

    static func localized(_ key: String) -> String {
        guard languageCode != "en" else { return key }
        return translations[key]?[languageCode] ?? key
    }
}

/// Resolves a localized string from the NotchFlow String Catalog (`Bundle.module`).
func loc(_ key: String) -> String {
    L10nCatalog.localized(key)
}

/// Formats a localized string with runtime arguments.
func locFormat(_ key: String, _ args: CVarArg...) -> String {
    let format = loc(key)
    return String(format: format, locale: Locale.current, arguments: args)
}

/// SwiftUI `Text` backed by the module String Catalog.
struct LocText: View {
    private let text: String

    init(_ key: String) {
        text = loc(key)
    }

    var body: some View {
        Text(text)
    }
}
