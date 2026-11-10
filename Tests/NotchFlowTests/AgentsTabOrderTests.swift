import XCTest
@testable import NotchFlow

@MainActor
final class AgentsTabOrderTests: XCTestCase {
    private func session(_ id: String, _ phase: AgentSessionPhase) -> AgentSession {
        AgentSession(
            id: id, agent: .claude, title: "Claude Code", detail: "", phase: phase,
            cwd: nil, terminalBundleID: nil, updatedAt: Date(), permission: nil, question: nil
        )
    }

    func testPromptsWaitingForYouComeFirstThenRunningThenFinished() {
        let ordered = AgentsTabView.ordered([
            session("done", .done),
            session("run1", .running),
            session("waiting", .waitingPermission),
            session("run2", .running),
            session("question", .waitingQuestion),
        ])
        XCTAssertEqual(ordered.map(\.id), ["waiting", "question", "run1", "run2", "done"])
    }
}
