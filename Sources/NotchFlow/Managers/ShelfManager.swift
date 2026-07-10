import Foundation
import UniformTypeIdentifiers

struct ShelfItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let url: URL
    let displayName: String
    let isDirectory: Bool
    let createdAt: Date

    init(id: UUID = UUID(), url: URL, displayName: String? = nil, isDirectory: Bool, createdAt: Date = .now) {
        self.id = id
        self.url = url
        self.displayName = displayName ?? url.lastPathComponent
        self.isDirectory = isDirectory
        self.createdAt = createdAt
    }
}

@MainActor
final class ShelfManager {
    var onItemsChange: (([ShelfItem]) -> Void)?

    private(set) var items: [ShelfItem] = [] {
        didSet { onItemsChange?(items) }
    }

    private let shelfDirectory: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        shelfDirectory = appSupport.appendingPathComponent("NotchFlow/Shelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: shelfDirectory, withIntermediateDirectories: true)
        loadPersistedItems()
    }

    func handleDrop(providers: [NSItemProvider], isPremium: Bool) async {
        var newItems: [ShelfItem] = []

        for provider in providers {
            if let url = await loadFileURL(from: provider) {
                if let item = try? linkOrCopy(url: url) {
                    newItems.append(item)
                }
            }
        }

        guard !newItems.isEmpty else { return }

        if isPremium, newItems.count > 1 {
            if let zipItem = try? createZipArchive(from: newItems) {
                newItems = [zipItem]
            }
        }

        if isPremium {
            items.insert(contentsOf: newItems, at: 0)
            if items.count > 12 {
                items = Array(items.prefix(12))
            }
        } else {
            items = Array(newItems.prefix(1))
        }

        persistIndex()
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        try? FileManager.default.removeItem(at: item.url)
        persistIndex()
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

        return ShelfItem(url: destination, isDirectory: isDirectory.boolValue)
    }

    private func persistIndex() {
        let payload = items.map { ["id": $0.id.uuidString, "path": $0.url.path] }
        let indexURL = shelfDirectory.appendingPathComponent("index.plist")
        (payload as NSArray).write(to: indexURL, atomically: true)
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
        return ShelfItem(url: archiveURL, displayName: archiveURL.lastPathComponent, isDirectory: false)
    }

    private func loadPersistedItems() {
        let indexURL = shelfDirectory.appendingPathComponent("index.plist")
        guard let payload = NSArray(contentsOf: indexURL) as? [[String: String]] else { return }

        items = payload.compactMap { entry in
            guard let path = entry["path"], let idString = entry["id"], let id = UUID(uuidString: idString) else {
                return nil
            }
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            return ShelfItem(id: id, url: url, isDirectory: isDirectory.boolValue)
        }
    }
}

import AppKit
