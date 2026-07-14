import Foundation

enum SettingsTab: String, Hashable, CaseIterable, Identifiable {
    case general
    case appearance
    case notifications
    case license
    case privacy
    case integrations

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: loc("General")
        case .appearance: loc("Appearance")
        case .notifications: loc("Notifications")
        case .license: loc("License")
        case .privacy: loc("Privacy")
        case .integrations: loc("Integrations")
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .notifications: "bell.badge"
        case .license: "key"
        case .privacy: "hand.raised"
        case .integrations: "link"
        }
    }
}
