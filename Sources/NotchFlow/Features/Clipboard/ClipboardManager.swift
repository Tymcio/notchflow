import AppKit
import Foundation
import UniformTypeIdentifiers

enum ClipboardEntryKind: String, Codable, Sendable {
    case text
    case url
    case image
}

struct ClipboardEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let kind: ClipboardEntryKind
    let value: String
    let createdAt: Date

    init(id: UUID = UUID(), kind: ClipboardEntryKind, value: String, createdAt: Date = .now) {
        self.id = id
        self.kind = kind
        self.value = value
        self.createdAt = createdAt
    }
}

@MainActor
final class ClipboardManager {
    var onEntriesChange: (([ClipboardEntry]) -> Void)?

    private(set) var entries: [ClipboardEntry] = [] {
        didSet { onEntriesChange?(entries) }
    }

    private var lastChangeCount = NSPasteboard.general.changeCount
    private var monitorTask: Task<Void, Never>?
    private let storageURL: URL

    init() {
        storageURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("NotchFlow/clipboard.json")
        load()
    }

    func setMonitoringEnabled(_ enabled: Bool) {
        monitorTask?.cancel()
        monitorTask = nil
        guard enabled else { return }

        monitorTask = Task {
            while !Task.isCancelled {
                captureIfChanged()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func captureIfChanged() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            let kind: ClipboardEntryKind = string.hasPrefix("http") ? .url : .text
            append(ClipboardEntry(kind: kind, value: string))
            return
        }

        if let url = pasteboard.string(forType: NSPasteboard.PasteboardType(rawValue: "public.url")) {
            append(ClipboardEntry(kind: .url, value: url))
        }
    }

    func copyBack(_ entry: ClipboardEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(entry.value, forType: .string)
    }

    func visibleEntries(isPremium: Bool) -> [ClipboardEntry] {
        let limit = isPremium ? NotchFlowConstants.premiumClipboardLimit : NotchFlowConstants.freeClipboardLimit
        return Array(entries.prefix(limit))
    }

    private func append(_ entry: ClipboardEntry) {
        entries.removeAll { $0.value == entry.value }
        entries.insert(entry, at: 0)
        if entries.count > NotchFlowConstants.premiumClipboardLimit {
            entries = Array(entries.prefix(NotchFlowConstants.premiumClipboardLimit))
        }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([ClipboardEntry].self, from: data) else { return }
        entries = decoded
    }
}
