import Foundation

/// Controls whether premium gates are enforced.
///
/// - `disabled` (default until public beta): every feature is unlocked for everyone.
///   License activation still works, so keys can be tested end-to-end.
/// - `enforced` (production): premium features require an active license.
///
/// Official builds enable enforcement by injecting `NFEnforceLicense = true` into
/// Info.plist (see `Scripts/package_app.sh` with `ENFORCE_LICENSE=1`). For local
/// testing, set the `NOTCHFLOW_ENFORCE_LICENSE=1` environment variable.
enum LicenseMode {
    case disabled
    case enforced

    static let current: LicenseMode = {
        if ProcessInfo.processInfo.environment["NOTCHFLOW_ENFORCE_LICENSE"] == "1" {
            return .enforced
        }
        if Bundle.main.object(forInfoDictionaryKey: "NFEnforceLicense") as? Bool == true {
            return .enforced
        }
        return .disabled
    }()

    var isEnforced: Bool {
        switch self {
        case .disabled: false
        case .enforced: true
        }
    }
}
