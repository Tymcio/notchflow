import Foundation

enum AppVersionInfo {
    static var displayString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (version?.isEmpty == false ? version : nil, build?.isEmpty == false ? build : nil) {
        case let (.some(v), .some(b)):
            return "\(NotchFlowConstants.appName) \(v) (\(b))"
        case let (.some(v), .none):
            return "\(NotchFlowConstants.appName) \(v)"
        case let (.none, .some(b)):
            return "\(NotchFlowConstants.appName) (\(b))"
        default:
            return NotchFlowConstants.appName
        }
    }
}
