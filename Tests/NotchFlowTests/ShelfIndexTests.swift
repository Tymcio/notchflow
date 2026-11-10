import XCTest
@testable import NotchFlow

@MainActor
final class ShelfIndexTests: XCTestCase {
    private var root: URL!
    private var shelf: URL!
    private var source: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchFlowShelfIndex-\(UUID().uuidString)", isDirectory: true)
        shelf = root.appendingPathComponent("Shelf", isDirectory: true)
        source = root.appendingPathComponent("Source", isDirectory: true)
        try FileManager.default.createDirectory(at: shelf, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testIndexLivesOutsideTheDropFolder() {
        let manager = ShelfManager(directory: shelf)
        XCTAssertEqual(manager.indexURL.deletingLastPathComponent().standardizedFileURL, root.standardizedFileURL)
        XCTAssertNotEqual(manager.indexURL.deletingLastPathComponent().standardizedFileURL, shelf.standardizedFileURL)
    }

    func testDroppingAFileNamedIndexPlistKeepsTheShelfIndex() throws {
        let note = source.appendingPathComponent("note.txt")
        try "note".write(to: note, atomically: true, encoding: .utf8)
        let collider = source.appendingPathComponent("index.plist")
        let colliderContents = Data("user data, not a shelf index".utf8)
        try colliderContents.write(to: collider)

        let manager = ShelfManager(directory: shelf)
        try manager.ingestDroppedFileForTesting(note, isPremium: true)
        try manager.ingestDroppedFileForTesting(collider, isPremium: true)

        let reloaded = ShelfManager(directory: shelf)
        let names = Set(reloaded.droppedItems.map(\.displayName))
        XCTAssertTrue(names.contains("note.txt"))
        XCTAssertTrue(names.contains("index.plist"))
        let droppedCollider = try XCTUnwrap(reloaded.droppedItems.first { $0.displayName == "index.plist" })
        XCTAssertEqual(try Data(contentsOf: droppedCollider.url), colliderContents)
    }

    func testLegacyIndexInsideTheShelfIsMigrated() throws {
        let kept = shelf.appendingPathComponent("kept.txt")
        try "kept".write(to: kept, atomically: true, encoding: .utf8)
        let legacy: [[String: String]] = [[
            "id": UUID().uuidString,
            "path": kept.path,
            "kind": "dropped",
            "displayName": "kept.txt",
            "isDirectory": "0",
        ]]
        let data = try PropertyListSerialization.data(fromPropertyList: legacy, format: .binary, options: 0)
        try data.write(to: shelf.appendingPathComponent("index.plist"))

        let manager = ShelfManager(directory: shelf)
        XCTAssertEqual(manager.droppedItems.map(\.displayName), ["kept.txt"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: manager.indexURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: shelf.appendingPathComponent("index.plist").path))
    }
}
