import AppKit
import Foundation
import UniformTypeIdentifiers

enum ShelfItemKind: String, Codable, Sendable {
    case pinned
    case dropped
}

struct ShelfItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let url: URL
    let displayName: String
    let isDirectory: Bool
    let createdAt: Date
    let kind: ShelfItemKind
    let originalPath: String?

    init(
        id: UUID = UUID(),
        url: URL,
        displayName: String? = nil,
        isDirectory: Bool,
        createdAt: Date = .now,
        kind: ShelfItemKind = .dropped,
        originalPath: String? = nil
    ) {
        self.id = id
        self.url = url
        self.displayName = displayName ?? url.lastPathComponent
        self.isDirectory = isDirectory
        self.createdAt = createdAt
        self.kind = kind
        self.originalPath = originalPath
    }

    var resolvedURL: URL {
        if kind == .pinned, let originalPath {
            return URL(fileURLWithPath: originalPath)
        }
        return url
    }
}

@MainActor
final class ShelfManager {
    var onItemsChange: (([ShelfItem]) -> Void)?

    private(set) var items: [ShelfItem] = [] {
        didSet { onItemsChange?(items) }
    }

    private let shelfDirectory: URL
    private let pinnedIndexURL: URL

    var pinnedItems: [ShelfItem] {
        items.filter { $0.kind == .pinned }
    }

    var droppedItems: [ShelfItem] {
        items.filter { $0.kind == .dropped }
    }

    init(directory: URL? = nil) {
        if let directory {
            shelfDirectory = directory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            shelfDirectory = appSupport.appendingPathComponent("NotchFlow/Shelf", isDirectory: true)
        }
        pinnedIndexURL = shelfDirectory.appendingPathComponent("pinned.plist")
        try? FileManager.default.createDirectory(at: shelfDirectory, withIntermediateDirectories: true)
        loadPersistedItems()
    }

    func handleDrop(providers: [NSItemProvider], isPremium: Bool, pinOnDrop: Bool = false) async {
        var newItems: [ShelfItem] = []

        for provider in providers {
            if let url = await loadFileURL(from: provider) {
                if pinOnDrop {
                    if let item = pinURL(url, isPremium: isPremium) {
                        newItems.append(item)
                    }
                } else if let item = try? linkOrCopy(url: url) {
                    newItems.append(item)
                }
            }
        }

        guard !newItems.isEmpty else { return }

        if !pinOnDrop {
            if isPremium, newItems.count > 1 {
                if let zipItem = try? createZipArchive(from: newItems) {
                    newItems = [zipItem]
                }
            }

            if isPremium {
                let dropped = droppedItems
                items = pinnedItems + Array((newItems + dropped).prefix(NotchFlowConstants.premiumDroppedShelfLimit))
            } else {
                items = pinnedItems + Array(newItems.prefix(NotchFlowConstants.freeDroppedShelfLimit))
            }
        }

        persistIndex()
    }

    #if DEBUG
    /// Test hook for ingesting a dropped file without NSItemProvider drag-and-drop.
    func ingestDroppedFileForTesting(_ url: URL, isPremium: Bool) throws {
        let item = try linkOrCopy(url: url)
        if isPremium {
            items = pinnedItems + Array(([item] + droppedItems).prefix(NotchFlowConstants.premiumDroppedShelfLimit))
        } else {
            items = pinnedItems + Array([item].prefix(NotchFlowConstants.freeDroppedShelfLimit))
        }
        persistIndex()
    }
    #endif

    func pinURL(_ url: URL, isPremium: Bool) -> ShelfItem? {
        let limit = isPremium ? NotchFlowConstants.premiumPinnedShelfLimit : NotchFlowConstants.freePinnedShelfLimit
        guard pinnedItems.count < limit else { return nil }

        let resolved = url.resolvingSymlinksInPath()
        let accessed = resolved.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                resolved.stopAccessingSecurityScopedResource()
            }
        }

        guard FileManager.default.fileExists(atPath: resolved.path) else { return nil }

        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory)

        guard let bookmark = makeBookmarkData(for: resolved),
              let bookmarkURL = writeBookmarkFile(bookmark) else {
            return nil
        }

        let item = ShelfItem(
            url: bookmarkURL,
            displayName: resolved.lastPathComponent,
            isDirectory: isDirectory.boolValue,
            kind: .pinned,
            originalPath: resolved.path
        )

        items.insert(item, at: 0)
        persistIndex()
        return item
    }

    func pinDroppedItem(_ item: ShelfItem, isPremium: Bool) {
        guard item.kind == .dropped else { return }
        let limit = isPremium ? NotchFlowConstants.premiumPinnedShelfLimit : NotchFlowConstants.freePinnedShelfLimit
        guard pinnedItems.count < limit else { return }

        if let originalPath = item.originalPath {
            let originalURL = URL(fileURLWithPath: originalPath)
            if FileManager.default.fileExists(atPath: originalURL.path) {
                if pinURL(originalURL, isPremium: isPremium) != nil {
                    remove(item)
                }
                return
            }
        }

        promoteShelfCopyToPinned(item)
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        if item.kind == .dropped || item.url.pathExtension == "bookmark" {
            try? FileManager.default.removeItem(at: item.url)
        }
        persistIndex()
    }

    func open(_ item: ShelfItem) {
        let opened: Bool
        switch item.kind {
        case .dropped:
            opened = openURL(item.resolvedURL)
        case .pinned:
            opened = openPinnedItem(item)
        }

        if !opened {
            presentOpenFailure(for: item)
        }
    }

    private func openPinnedItem(_ item: ShelfItem) -> Bool {
        if let resolved = resolveBookmarkURL(for: item) {
            let accessed = resolved.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    resolved.stopAccessingSecurityScopedResource()
                }
            }
            if openURL(resolved) {
                return true
            }
        }

        if let originalPath = item.originalPath {
            return openURL(URL(fileURLWithPath: originalPath))
        }

        return false
    }

    @discardableResult
    private func openURL(_ url: URL) -> Bool {
        let resolved = url.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: resolved.path) else {
            NotchFlowLog.storage.error("Shelf item missing on disk: \(resolved.path, privacy: .public)")
            return false
        }

        NSApp.activate(ignoringOtherApps: true)
        let opened = NSWorkspace.shared.open(resolved)
        if !opened {
            NotchFlowLog.storage.error("NSWorkspace failed to open shelf item: \(resolved.path, privacy: .public)")
        }
        return opened
    }

    private func resolveBookmarkURL(for item: ShelfItem) -> URL? {
        guard item.kind == .pinned,
              item.url.pathExtension == "bookmark",
              let bookmark = try? Data(contentsOf: item.url) else {
            return nil
        }

        var isStale = false
        let optionSets: [URL.BookmarkResolutionOptions] = [[], [.withSecurityScope]]
        for options in optionSets {
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: options,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                return url
            }
        }
        return nil
    }

    private func promoteShelfCopyToPinned(_ item: ShelfItem) {
        guard FileManager.default.fileExists(atPath: item.url.path) else { return }

        let permanentURL = permanentPinnedFileURL(for: item)
        let fileURL: URL
        if item.url != permanentURL {
            do {
                if FileManager.default.fileExists(atPath: permanentURL.path) {
                    try FileManager.default.removeItem(at: permanentURL)
                }
                try FileManager.default.moveItem(at: item.url, to: permanentURL)
                fileURL = permanentURL
            } catch {
                NotchFlowLog.storage.error("Failed to promote shelf item: \(error.localizedDescription, privacy: .public)")
                fileURL = item.url
            }
        } else {
            fileURL = item.url
        }

        guard let bookmark = makeBookmarkData(for: fileURL),
              let bookmarkURL = writeBookmarkFile(bookmark) else {
            return
        }

        let pinned = ShelfItem(
            id: item.id,
            url: bookmarkURL,
            displayName: item.displayName,
            isDirectory: item.isDirectory,
            createdAt: item.createdAt,
            kind: .pinned,
            originalPath: fileURL.path
        )

        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = pinned
        persistIndex()
    }

    private func permanentPinnedFileURL(for item: ShelfItem) -> URL {
        shelfDirectory.appendingPathComponent("pinned-\(item.id.uuidString)-\(item.displayName)")
    }

    private func makeBookmarkData(for url: URL) -> Data? {
        let resolved = url.resolvingSymlinksInPath()
        let options: URL.BookmarkCreationOptions = resolved.path.hasPrefix(shelfDirectory.path)
            ? [.minimalBookmark]
            : [.withSecurityScope]
        return try? resolved.bookmarkData(
            options: options,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private func writeBookmarkFile(_ bookmark: Data) -> URL? {
        let bookmarkURL = shelfDirectory.appendingPathComponent("pin-\(UUID().uuidString).bookmark")
        do {
            try SecureFileWriter.write(bookmark, to: bookmarkURL)
            return bookmarkURL
        } catch {
            NotchFlowLog.storage.error("Failed to write shelf bookmark: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func presentOpenFailure(for item: ShelfItem) {
        let alert = NSAlert()
        alert.messageText = loc("Cannot open file")
        alert.informativeText = locFormat("\"%@\" is unavailable. Remove the shortcut from the shelf and add it again.", item.displayName)
        alert.alertStyle = .warning
        alert.addButton(withTitle: loc("OK"))
        alert.runModal()
    }

    func revealInFinder(_ item: ShelfItem) {
        let url = resolvePinnedURL(for: item) ?? item.resolvedURL
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func resolvePinnedURL(for item: ShelfItem) -> URL? {
        guard item.kind == .pinned else { return item.resolvedURL }

        if let resolved = resolveBookmarkURL(for: item) {
            return resolved
        }

        if let originalPath = item.originalPath {
            let url = URL(fileURLWithPath: originalPath)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        return nil
    }

    private func loadFileURL(from provider: NSItemProvider) async -> URL? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            return await withCheckedContinuation { continuation in
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        continuation.resume(returning: url)
                    } else if let url = item as? URL {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            return await withCheckedContinuation { continuation in
                provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                    continuation.resume(returning: item as? URL)
                }
            }
        }

        return nil
    }

    private func linkOrCopy(url: URL) throws -> ShelfItem {
        let destination = shelfDirectory.appendingPathComponent(url.lastPathComponent)
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        do {
            try fileManager.linkItem(at: url, to: destination)
        } catch {
            try fileManager.copyItem(at: url, to: destination)
        }

        var isDirectory: ObjCBool = false
        fileManager.fileExists(atPath: destination.path, isDirectory: &isDirectory)

        return ShelfItem(
            url: destination,
            isDirectory: isDirectory.boolValue,
            kind: .dropped,
            originalPath: url.resolvingSymlinksInPath().path
        )
    }

    private func persistIndex() {
        let payload = items.map { item -> [String: String] in
            var entry: [String: String] = [
                "id": item.id.uuidString,
                "path": item.url.path,
                "kind": item.kind.rawValue,
                "displayName": item.displayName,
                "isDirectory": item.isDirectory ? "1" : "0"
            ]
            if let originalPath = item.originalPath {
                entry["originalPath"] = originalPath
            }
            return entry
        }
        let indexURL = shelfDirectory.appendingPathComponent("index.plist")
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .binary, options: 0)
            try SecureFileWriter.write(data, to: indexURL)
        } catch {
            NotchFlowLog.storage.error("Failed to persist shelf index: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func createZipArchive(from items: [ShelfItem]) throws -> ShelfItem {
        let archiveURL = shelfDirectory.appendingPathComponent("drop-\(UUID().uuidString.prefix(8)).zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-j", archiveURL.path, "--"] + items.map(\.url.path)
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "NotchFlow.Shelf", code: 1)
        }
        return ShelfItem(url: archiveURL, displayName: archiveURL.lastPathComponent, isDirectory: false, kind: .dropped)
    }

    private func loadPersistedItems() {
        let indexURL = shelfDirectory.appendingPathComponent("index.plist")
        guard let payload = NSArray(contentsOf: indexURL) as? [[String: String]] else { return }

        items = payload.compactMap { entry in
            guard let path = entry["path"],
                  let idString = entry["id"],
                  let id = UUID(uuidString: idString) else {
                return nil
            }

            let kind = ShelfItemKind(rawValue: entry["kind"] ?? ShelfItemKind.dropped.rawValue) ?? .dropped
            let url = URL(fileURLWithPath: path)

            if kind == .dropped, !FileManager.default.fileExists(atPath: path) {
                return nil
            }

            if kind == .pinned, !FileManager.default.fileExists(atPath: path) {
                return nil
            }

            let isDirectory = entry["isDirectory"] == "1"
            let displayName = entry["displayName"]
            let originalPath = entry["originalPath"]

            return ShelfItem(
                id: id,
                url: url,
                displayName: displayName,
                isDirectory: isDirectory,
                kind: kind,
                originalPath: originalPath
            )
        }
    }
}
