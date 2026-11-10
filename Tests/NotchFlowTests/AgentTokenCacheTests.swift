import Foundation
import XCTest
@testable import NotchFlow

final class AgentTokenCacheTests: XCTestCase {
    func testRotatedTokenCacheMatchesFingerprintOnly() {
        let cache = RotatedTokenCache()
        XCTAssertNil(cache.session(matching: "abc"))

        let session = RotatedTokenSession(fingerprint: "abc", accessToken: "access", refreshToken: "refresh")
        cache.store(session)
        XCTAssertEqual(cache.session(matching: "abc"), session)
        XCTAssertNil(cache.session(matching: "other"), "a different stored login must not reuse the rotated pair")

        cache.clear()
        XCTAssertNil(cache.session(matching: "abc"))
    }

    func testLegacyPlaintextTokenCachesAreRemoved() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("notchflow-legacy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let cursor = directory.appendingPathComponent("cursor-oauth.json")
        let grokBot = directory.appendingPathComponent("grokbot-oauth.json")
        let unrelated = directory.appendingPathComponent("notchflow-agent-hook.sh")
        for url in [cursor, grokBot, unrelated] {
            try Data(#"{"accessToken":"secret"}"#.utf8).write(to: url)
        }

        let removed = AgentUsageClient.removeLegacyTokenCaches(in: directory)

        XCTAssertEqual(Set(removed.map(\.lastPathComponent)), ["cursor-oauth.json", "grokbot-oauth.json"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: cursor.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: grokBot.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
        XCTAssertTrue(AgentUsageClient.removeLegacyTokenCaches(in: directory).isEmpty)
    }

    func testUsageProvidersNoLongerReferenceDiskTokenCaches() throws {
        // Guard against the plaintext cache coming back in a later refactor.
        let usageDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/NotchFlow/Features/Agents/Usage", isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(at: usageDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "AgentUsageClient.swift" }
        XCTAssertFalse(files.isEmpty)
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(source.contains("SecureFileWriter"), "\(file.lastPathComponent) writes to disk")
            XCTAssertFalse(source.contains("oauth.json"), "\(file.lastPathComponent) references a token cache file")
        }
    }
}
