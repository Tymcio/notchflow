import XCTest
@testable import NotchFlow

final class AgentDetectionTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("nf-detect-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private func makeDirectory(_ path: String) throws {
        try FileManager.default.createDirectory(at: home.appendingPathComponent(path), withIntermediateDirectories: true)
    }

    func testNothingIsDetectedInAnEmptyHome() {
        XCTAssertEqual(AgentDetection.detectedAgents(home: home, binaryDirectories: []), [])
    }

    func testConfigFoldersMarkAgentsInstalled() throws {
        for path in [".codex", ".copilot", ".qwen", ".gemini", ".config/opencode", ".config/kilo", ".config/crush", ".factory"] {
            try makeDirectory(path)
        }
        XCTAssertEqual(
            AgentDetection.detectedAgents(home: home, binaryDirectories: []),
            [.codex, .copilot, .qwen, .gemini, .opencode, .kilo, .crush, .droid]
        )
    }

    func testAFileWithAConfigFolderNameDoesNotCount() throws {
        try "x".write(to: home.appendingPathComponent(".codex"), atomically: true, encoding: .utf8)
        XCTAssertFalse(AgentDetection.isInstalled(.codex, home: home, binaryDirectories: []))
    }

    func testBinariesInStandardFoldersMarkAgentsInstalled() throws {
        try makeDirectory(".local/bin")
        let bin = home.appendingPathComponent(".local/bin")
        for name in ["crush", "droid", "kilocode"] {
            FileManager.default.createFile(atPath: bin.appendingPathComponent(name).path, contents: Data())
        }
        let detected = AgentDetection.detectedAgents(
            home: home,
            binaryDirectories: AgentDetection.binaryDirectories(home: home).filter { $0.path.hasPrefix(home.path) }
        )
        XCTAssertEqual(detected, [.kilo, .crush, .droid])
    }

    func testStandardBinaryFoldersIncludeUserAndHomebrewLocations() {
        let paths = AgentDetection.binaryDirectories(home: home).map(\.path)
        XCTAssertTrue(paths.contains(home.appendingPathComponent(".local/bin").path))
        XCTAssertTrue(paths.contains("/opt/homebrew/bin"))
        XCTAssertTrue(paths.contains("/usr/local/bin"))
        XCTAssertTrue(paths.contains(home.appendingPathComponent(".npm-global/bin").path))
        XCTAssertTrue(paths.contains(home.appendingPathComponent(".bun/bin").path))
    }

    func testCapabilitiesMatchWhatEachAgentSupports() {
        for agent: AgentKind in [.claude, .codex, .copilot, .qwen] {
            XCTAssertEqual(agent.hookCapability, .answersInNotch, "\(agent)")
        }
        for agent: AgentKind in [.gemini, .opencode, .kilo, .crush, .droid, .cursor, .grok] {
            XCTAssertEqual(agent.hookCapability, .statusOnly, "\(agent)")
        }
        XCTAssertNil(AgentKind.grokbot.hookCapability)
        XCTAssertEqual(Set(AgentKind.connectableAgents), Set(AgentKind.allCases.filter { $0.hookCapability != nil }))
    }

    func testRawNamesMapToTheNewAgents() {
        XCTAssertEqual(AgentKind.from(raw: "copilot"), .copilot)
        XCTAssertEqual(AgentKind.from(raw: "github-copilot"), .copilot)
        XCTAssertEqual(AgentKind.from(raw: "qwen"), .qwen)
        XCTAssertEqual(AgentKind.from(raw: "kilocode"), .kilo)
        XCTAssertEqual(AgentKind.from(raw: "crush"), .crush)
        XCTAssertEqual(AgentKind.from(raw: "factory"), .droid)
    }
}
