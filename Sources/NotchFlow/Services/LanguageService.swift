import AppKit
import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case polish = "pl"
    case german = "de"
    case italian = "it"
    case spanish = "es"

    var id: String { rawValue }

    /// Language names are shown in their own language (standard practice), so they are not localized.
    var displayName: String {
        switch self {
        case .system: loc("System default")
        case .english: "English"
        case .polish: "Polski"
        case .german: "Deutsch"
        case .italian: "Italiano"
        case .spanish: "Español"
        }
    }
}

/// Per-app language override via the `AppleLanguages` user default.
/// Bundle localization is resolved at process start, so applying a change relaunches the app.
@MainActor
enum LanguageService {
    private static let key = "AppleLanguages"

    static var current: AppLanguage {
        guard let override = appLanguageOverride else {
            return .system
        }
        return AppLanguage(rawValue: override) ?? .system
    }

    static func apply(_ language: AppLanguage) {
        guard language != current else { return }
        if language == .system {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set([language.rawValue], forKey: key)
        }
        UserDefaults.standard.synchronize()
        relaunch()
    }

    private static var appLanguageOverride: String? {
        guard let bundleID = Bundle.main.bundleIdentifier,
              let domain = UserDefaults.standard.persistentDomain(forName: bundleID),
              let languages = domain[key] as? [String],
              let first = languages.first else {
            return nil
        }
        return String(first.prefix(2))
    }

    private static func relaunch() {
        let bundlePath = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Wait for this instance to exit before opening the new one, so we never run two copies.
        process.arguments = ["-c", "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.1; done; /usr/bin/open \"\(bundlePath)\""]
        try? process.run()
        NSApp.terminate(nil)
    }
}
