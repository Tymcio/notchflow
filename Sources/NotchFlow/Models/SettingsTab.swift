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
        case .general: "Ogólne"
        case .appearance: "Wygląd"
        case .notifications: "Powiadomienia"
        case .license: "Licencja"
        case .privacy: "Prywatność"
        case .integrations: "Integracje"
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
