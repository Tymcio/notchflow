import Foundation

/// SwiftPM's generated `Bundle.module` looks for `NotchFlow_NotchFlow.bundle` at the
/// `.app` root (sibling of `Contents`). That path is invalid for signed macOS apps
/// (`codesign` rejects unsealed root contents), so packaging places the bundle in
/// `Contents/Resources/` instead. Always load resources through this helper.
enum ResourceBundle {
    static let bundle: Bundle = {
        let name = "NotchFlow_NotchFlow.bundle"
        let candidates: [URL?] = [
            Bundle.main.resourceURL?.appendingPathComponent(name),
            Bundle.main.bundleURL
                .appendingPathComponent("Contents/Resources", isDirectory: true)
                .appendingPathComponent(name),
            Bundle.main.bundleURL.appendingPathComponent(name),
            Bundle.main.url(forResource: "NotchFlow_NotchFlow", withExtension: "bundle"),
        ]

        for candidate in candidates {
            guard let path = candidate?.path, let found = Bundle(path: path) else { continue }
            return found
        }

        // Last resort: generated Bundle.module (works for `swift run` / local .build).
        return .module
    }()
}
