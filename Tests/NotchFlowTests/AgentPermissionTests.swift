import XCTest
@testable import NotchFlow

@MainActor
final class AgentPermissionTests: XCTestCase {
    private func permissionEvent(session: String, id: String, summary: String) -> [String: Any] {
        [
            "agent": "claude",
            "event": "permission",
            "sessionId": session,
            "permissionId": id,
            "toolName": "Bash",
            "summary": summary,
        ]
    }

    func testOneAllowNeverApprovesAPromptTheUserDidNotSee() {
        let manager = AgentSessionManager()
        manager.ingestEvent(permissionEvent(session: "s1", id: "a", summary: "ls"))
        manager.ingestEvent(permissionEvent(session: "s1", id: "b", summary: "rm -rf build"))

        XCTAssertEqual(manager.sessions.first?.permission?.id, "b")

        manager.decidePermission(id: "b", decision: .allow)
        XCTAssertEqual(manager.permissionDecision(id: "b"), .allow)
        XCTAssertNil(manager.permissionDecision(id: "a"))

        // The displaced prompt comes back instead of disappearing.
        XCTAssertEqual(manager.sessions.first?.permission?.id, "a")
        XCTAssertEqual(manager.sessions.first?.phase, .waitingPermission)

        manager.decidePermission(id: "a", decision: .deny)
        XCTAssertEqual(manager.permissionDecision(id: "a"), .deny)
        XCTAssertNil(manager.sessions.first?.permission)
    }

    func testToolActivityDropsQueuedPrompts() {
        let manager = AgentSessionManager()
        manager.ingestEvent(permissionEvent(session: "s1", id: "a", summary: "ls"))
        manager.ingestEvent(permissionEvent(session: "s1", id: "b", summary: "pwd"))
        manager.ingestEvent(["agent": "claude", "event": "tool", "sessionId": "s1", "detail": "Bash"])

        XCTAssertNil(manager.sessions.first?.permission)
        manager.decidePermission(id: "b", decision: .allow)
        XCTAssertNil(manager.sessions.first?.permission)
    }

    func testClaudeNotificationKeepsThePendingPrompt() {
        let manager = AgentSessionManager()
        manager.ingestEvent(permissionEvent(session: "s1", id: "a", summary: "npm test"))
        // Claude Code sends this right after PermissionRequest.
        manager.ingestEvent(["agent": "claude", "event": "notification", "sessionId": "s1", "detail": ""])

        let session = manager.sessions.first
        XCTAssertEqual(session?.permission?.id, "a")
        XCTAssertEqual(session?.phase, .waitingPermission)
        XCTAssertEqual(session?.detail, "npm test")
    }

    func testNotificationAloneDoesNotInventAPrompt() {
        let manager = AgentSessionManager()
        manager.ingestEvent(["agent": "claude", "event": "notification", "sessionId": "s2", "detail": ""])
        XCTAssertNil(manager.sessions.first?.permission)
        XCTAssertEqual(manager.sessions.first?.phase, .running)
    }

    func testHookTreatsNotificationSeparatelyAndReportsTheHostApp() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/NotchFlow/Resources/AgentHooks/notchflow-agent-hook.sh")
        let script = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(script.contains("Notification) NF_EVENT=\"notification\""))
        XCTAssertTrue(script.contains("BUNDLE=\"${__CFBundleIdentifier:-}\""))
    }

    func testHookScriptNeverDecidesForCursorAndUsesUniqueIDs() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/NotchFlow/Resources/AgentHooks/notchflow-agent-hook.sh")
        let script = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(script.contains("\"permission\":\"allow\""))
        XCTAssertFalse(script.contains("$(date +%s)"))
        XCTAssertTrue(script.contains("PERMISSION_ID=\"$(/usr/bin/uuidgen)\""))
    }
}
