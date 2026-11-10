import Foundation
import XCTest
@testable import NotchFlow

final class ExternalConfigFileTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("notchflow-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func mode(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    private func json(at url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    func testSymlinkedSettingsStayASymlinkAndTheRealFileIsUpdated() throws {
        let real = directory.appendingPathComponent("dotfiles/settings.json")
        try FileManager.default.createDirectory(at: real.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"model":"opus"}"#.utf8).write(to: real)
        let link = directory.appendingPathComponent("settings.json")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "dotfiles/settings.json")

        try ExternalConfigFile.updateJSONObject(at: link) { $0["hooks"] = ["Stop": []] }

        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: link.path)
        XCTAssertEqual(destination, "dotfiles/settings.json")
        let root = try json(at: real)
        XCTAssertEqual(root["model"] as? String, "opus")
        XCTAssertNotNil(root["hooks"])
    }

    func testExistingPermissionsArePreserved() throws {
        let file = directory.appendingPathComponent("hooks.json")
        try Data(#"{"version":1}"#.utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)

        try ExternalConfigFile.updateJSONObject(at: file) { $0["hooks"] = [:] as [String: Any] }

        XCTAssertEqual(try mode(of: file), 0o644)
    }

    func testNewFilesAreOwnerOnly() throws {
        let file = directory.appendingPathComponent("nested/settings.json")
        try ExternalConfigFile.updateJSONObject(at: file) { $0["hooks"] = [:] as [String: Any] }
        XCTAssertEqual(try mode(of: file), 0o600)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ExternalConfigFile.backupURL(for: file).path),
                       "nothing to back up for a new file")
    }

    func testBackupIsWrittenOnceBeforeTheFirstChange() throws {
        let file = directory.appendingPathComponent("settings.json")
        let original = Data(#"{"theme":"dark"}"#.utf8)
        try original.write(to: file)

        try ExternalConfigFile.updateJSONObject(at: file) { $0["first"] = true }
        try ExternalConfigFile.updateJSONObject(at: file) { $0["second"] = true }

        let backup = ExternalConfigFile.backupURL(for: file)
        XCTAssertEqual(try Data(contentsOf: backup), original)
        let root = try json(at: file)
        XCTAssertEqual(root["first"] as? Bool, true)
        XCTAssertEqual(root["second"] as? Bool, true)
    }

    func testNonObjectRootIsLeftUntouched() throws {
        let file = directory.appendingPathComponent("settings.json")
        let original = Data(#"["not", "an", "object"]"#.utf8)
        try original.write(to: file)

        XCTAssertThrowsError(try ExternalConfigFile.updateJSONObject(at: file) { $0["hooks"] = [:] as [String: Any] }) { error in
            XCTAssertEqual(error as? ExternalConfigError, .notJSONObject(path: file.path))
        }
        XCTAssertEqual(try Data(contentsOf: file), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ExternalConfigFile.backupURL(for: file).path))
    }

    func testUnparseableFileIsLeftUntouched() throws {
        let file = directory.appendingPathComponent("hooks.json")
        let original = Data("{ \"version\": 1, // comment\n }".utf8)
        try original.write(to: file)

        XCTAssertThrowsError(try ExternalConfigFile.updateJSONObject(at: file) { $0["hooks"] = [:] as [String: Any] })
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testMissingFileIsNotCreatedWhenOnlyScrubbing() throws {
        let file = directory.appendingPathComponent("absent.json")
        let wrote = try ExternalConfigFile.updateJSONObject(at: file, createIfMissing: false) { $0["x"] = 1 }
        XCTAssertFalse(wrote)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testUnchangedContentIsNotRewritten() throws {
        let file = directory.appendingPathComponent("settings.json")
        try ExternalConfigFile.updateJSONObject(at: file) { $0["a"] = 1 }
        let wrote = try ExternalConfigFile.updateJSONObject(at: file) { $0["a"] = 1 }
        XCTAssertFalse(wrote)
    }

    func testClaudeHookMergeKeepsOtherHooksAndReplacesOldNotchFlowEntries() throws {
        var root: [String: Any] = [
            "hooks": [
                "Stop": [
                    ["hooks": [["type": "command", "command": "say done"]]],
                    ["hooks": [["type": "command", "command": "'/old/notchflow-agent-hook.sh'"]]],
                ],
            ],
        ]
        AgentHooksInstaller.mergeClaudeHooks(into: &root, scriptPath: "/new/notchflow-agent-hook.sh")
        let stop = try XCTUnwrap((root["hooks"] as? [String: Any])?["Stop"] as? [Any])
        XCTAssertEqual(stop.count, 2)
        let encoded = String(describing: stop)
        XCTAssertTrue(encoded.contains("say done"))
        XCTAssertTrue(encoded.contains("/new/notchflow-agent-hook.sh"))
        XCTAssertFalse(encoded.contains("/old/notchflow-agent-hook.sh"))
    }
}
