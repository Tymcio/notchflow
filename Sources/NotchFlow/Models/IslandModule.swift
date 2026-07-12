import Foundation

enum IslandModule: String, CaseIterable, Identifiable, Sendable {
    case media
    case calendar
    case shelf
    case focus
    case notes
    case clipboard
    case mirror

    var id: String { rawValue }

    var title: String {
        switch self {
        case .media: "Muzyka"
        case .calendar: "Kalendarz"
        case .shelf: "Półka"
        case .focus: "Minutnik"
        case .notes: "Notatki"
        case .clipboard: "Schowek"
        case .mirror: "Lustro"
        }
    }

    var systemImage: String {
        switch self {
        case .media: "music.note"
        case .calendar: "calendar"
        case .shelf: "tray.and.arrow.down.fill"
        case .focus: "timer"
        case .notes: "note.text"
        case .clipboard: "doc.on.clipboard"
        case .mirror: "camera.fill"
        }
    }

    static var leadingTabs: [IslandModule] { [.media, .calendar, .shelf] }
    static var trailingTabs: [IslandModule] { [.focus, .notes, .clipboard, .mirror] }

    var requiresPremium: Bool {
        switch self {
        case .mirror: true
        default: false
        }
    }

    /// Modules with long scrollable content use the configured max height instead of intrinsic sizing.
    var prefersIntrinsicExpandedHeight: Bool {
        switch self {
        case .clipboard:
            false
        default:
            true
        }
    }

    /// Reasonable first-pass content height before intrinsic measurement completes.
    var estimatedContentHeight: CGFloat {
        switch self {
        case .calendar: 440
        case .media: 92
        case .shelf: 132
        case .focus: 188
        case .notes: 156
        case .mirror: 196
        case .clipboard: NotchFlowConstants.maximumExpandedContentHeight
        }
    }

    var estimatedTotalExpandedHeight: CGFloat {
        NotchFlowConstants.expandedTotalHeight(forContentHeight: estimatedContentHeight)
    }
}
