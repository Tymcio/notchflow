import AppKit
import XCTest
@testable import NotchFlow

@MainActor
final class ShelfManagerTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() async throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchFlowShelfTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testPinURLResolvesToOriginalFile() {
        let source = tempDirectory.appendingPathComponent("document.txt")
        try? "hello".write(to: source, atomically: true, encoding: .utf8)

        let manager = ShelfManager(directory: tempDirectory)
        let item = manager.pinURL(source, isPremium: true)
        XCTAssertNotNil(item)

        let resolved = manager.resolvePinnedURL(for: item!)
        XCTAssertEqual(
            resolved?.standardizedFileURL.path,
            source.standardizedFileURL.path
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testPinDroppedItemKeepsFileOnDisk() throws {
        let source = tempDirectory.appendingPathComponent("drop-me.txt")
        try "drop".write(to: source, atomically: true, encoding: .utf8)

        let manager = ShelfManager(directory: tempDirectory)
        try manager.ingestDroppedFileForTesting(source, isPremium: true)

        let dropped = try XCTUnwrap(manager.droppedItems.first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dropped.url.path))

        manager.pinDroppedItem(dropped, isPremium: true)

        let pinned = try XCTUnwrap(manager.pinnedItems.first)
        XCTAssertTrue(manager.droppedItems.isEmpty)

        let pinnedPath = pinned.originalPath ?? pinned.resolvedURL.path
        XCTAssertTrue(FileManager.default.fileExists(atPath: pinnedPath))
    }

    func testPersistedPinnedItemsReload() {
        let source = tempDirectory.appendingPathComponent("persist.txt")
        try? "persist".write(to: source, atomically: true, encoding: .utf8)

        let manager = ShelfManager(directory: tempDirectory)
        XCTAssertNotNil(manager.pinURL(source, isPremium: true))

        let reloaded = ShelfManager(directory: tempDirectory)
        XCTAssertEqual(reloaded.pinnedItems.count, 1)
        XCTAssertEqual(reloaded.pinnedItems.first?.displayName, "persist.txt")
    }

    func testRemovePinnedItemDeletesBookmark() {
        let source = tempDirectory.appendingPathComponent("remove-me.txt")
        try? "remove".write(to: source, atomically: true, encoding: .utf8)

        let manager = ShelfManager(directory: tempDirectory)
        let item = manager.pinURL(source, isPremium: true)
        XCTAssertNotNil(item)

        let bookmarkPath = item!.url.path
        manager.remove(item!)

        XCTAssertTrue(manager.pinnedItems.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: bookmarkPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }
}

@MainActor
final class NotchFlowLimitsTests: XCTestCase {
    func testFreePremiumLimitsMatchDocumentation() {
        XCTAssertEqual(NotchFlowConstants.freeNotesLimit, 5)
        XCTAssertEqual(NotchFlowConstants.freeClipboardLimit, 5)
        XCTAssertEqual(NotchFlowConstants.premiumClipboardLimit, 50)
        XCTAssertEqual(NotchFlowConstants.freePinnedShelfLimit, 3)
        XCTAssertEqual(NotchFlowConstants.premiumPinnedShelfLimit, 20)
        XCTAssertEqual(NotchFlowConstants.freeDroppedShelfLimit, 1)
        XCTAssertEqual(NotchFlowConstants.premiumDroppedShelfLimit, 12)
    }

    func testClipboardVisibleEntriesRespectPremiumLimit() {
        let manager = ClipboardManager()
        let entries = (0..<60).map { index in
            ClipboardEntry(kind: .text, value: "entry-\(index)", createdAt: .now)
        }
        manager.setEntriesForTesting(entries)

        let freeVisible = manager.visibleEntries(isPremium: false)
        XCTAssertEqual(freeVisible.count, NotchFlowConstants.freeClipboardLimit)

        let premiumVisible = manager.visibleEntries(isPremium: true)
        XCTAssertEqual(premiumVisible.count, NotchFlowConstants.premiumClipboardLimit)
    }
}
