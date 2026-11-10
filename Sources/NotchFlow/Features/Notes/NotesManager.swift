import Foundation

@MainActor
final class NotesManager {
    var onNotesChange: (([NoteItem]) -> Void)?

    /// `nil` keeps notes in memory only: nothing is read from or written to disk.
    private let storageURL: URL?
    private(set) var notes: [NoteItem] = [] {
        didSet { onNotesChange?(notes) }
    }

    convenience init() {
        self.init(
            storageURL: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("NotchFlow/notes.json")
        )
    }

    init(storageURL: URL?) {
        self.storageURL = storageURL
        load()
    }

    func reload() {
        load()
    }

    func visibleNotes(isPremium: Bool) -> [NoteItem] {
        let limit = isPremium ? notes.count : NotchFlowConstants.freeNotesLimit
        return Array(notes.prefix(limit))
    }

    func append(text: String, isPremium: Bool) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if !isPremium, notes.count >= NotchFlowConstants.freeNotesLimit {
            throw NotesError.limitReached
        }

        notes.insert(NoteItem(text: trimmed), at: 0)
        persist()
    }

    /// Replaces every note (pinned first, then newest first) and saves them.
    func setNotes(_ newNotes: [NoteItem]) {
        notes = Self.sorted(newNotes)
        persist()
    }

    func remove(_ note: NoteItem) {
        notes.removeAll { $0.id == note.id }
        persist()
    }

    func togglePin(_ note: NoteItem, isPremium: Bool) {
        guard isPremium else { return }
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[index].isPinned.toggle()
        notes = Self.sorted(notes)
        persist()
    }

    private static func sorted(_ notes: [NoteItem]) -> [NoteItem] {
        notes.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func persist() {
        guard let storageURL else { return }
        do {
            let data = try JSONEncoder().encode(notes)
            try SecureFileWriter.write(data, to: storageURL)
        } catch {
            NotchFlowLog.storage.error("Failed to persist notes: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func load() {
        guard let storageURL else { return }
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([NoteItem].self, from: data) else {
            notes = []
            return
        }
        notes = Self.sorted(decoded)
    }
}

enum NotesError: LocalizedError {
    case limitReached

    var errorDescription: String? {
        switch self {
        case .limitReached: locFormat("Free plan allows up to %lld notes.", NotchFlowConstants.freeNotesLimit)
        }
    }
}
