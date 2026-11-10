import XCTest
@testable import NotchFlow

/// Status-only agents pulse the notch without Allow / Deny; notifications never clear a prompt.
@MainActor
final class AgentMonitorOnlyTests: XCTestCase {
    func testAttentionFromStatusOnlyAgentsPulsesWithoutAllowAndDeny() {
        for agent in ["gemini", "opencode", "kilo", "crush", "droid"] {
            let manager = AgentSessionManager()
            var pulsed: [AgentSession] = []
            manager.onNeedsAttention = { pulsed.append($0) }
            manager.ingestEvent(["agent": agent, "event": "attention", "sessionId": "s1", "detail": "rm -rf build"])

            let session = manager.sessions.first
            XCTAssertEqual(session?.agent, AgentKind.from(raw: agent), agent)
            XCTAssertEqual(session?.phase, .waitingPermission, agent)
            XCTAssertNil(session?.permission, agent)
            XCTAssertEqual(session?.showsNotchApproval, false, agent)
            XCTAssertEqual(pulsed.count, 1, agent)
        }
    }

    func testToolActivityAfterAttentionReturnsToRunning() {
        let manager = AgentSessionManager()
        manager.ingestEvent(["agent": "crush", "event": "attention", "sessionId": "s1", "detail": "rm"])
        manager.ingestEvent(["agent": "crush", "event": "progress", "sessionId": "s1", "detail": ""])
        XCTAssertEqual(manager.sessions.first?.phase, .running)
    }

    func testNotificationsKeepPendingPromptsForEveryAnsweringAgent() {
        for agent in ["codex", "qwen", "copilot"] {
            let manager = AgentSessionManager()
            manager.ingestEvent([
                "agent": agent, "event": "permission", "sessionId": "s1",
                "permissionId": "p-\(agent)", "toolName": "Bash", "summary": "npm test",
            ])
            manager.ingestEvent(["agent": agent, "event": "notification", "sessionId": "s1", "detail": ""])

            let session = manager.sessions.first
            XCTAssertEqual(session?.permission?.id, "p-\(agent)", agent)
            XCTAssertEqual(session?.phase, .waitingPermission, agent)
            XCTAssertEqual(session?.showsNotchApproval, true, agent)
            XCTAssertEqual(session?.detail, "npm test", agent)
        }
    }

    func testNewAgentsShowTheirOwnNames() {
        let manager = AgentSessionManager()
        manager.ingestEvent(["agent": "copilot", "event": "session.started", "sessionId": "a"])
        manager.ingestEvent(["agent": "droid", "event": "session.started", "sessionId": "b"])
        XCTAssertEqual(Set(manager.sessions.map(\.title)), ["Copilot CLI", "Droid"])
    }
}
