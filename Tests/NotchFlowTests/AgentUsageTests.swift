import XCTest
@testable import NotchFlow

final class AgentUsageParserTests: XCTestCase {
    func testClaudeWindowsAndExtraCredits() throws {
        let json: [String: Any] = [
            "five_hour": [
                "utilization": 47.0,
                "resets_at": "2026-08-19T12:00:00Z",
            ],
            "seven_day": [
                "utilization": 30,
                "resets_at": "2026-08-25T16:59:59.951713+00:00",
            ],
            "seven_day_opus": NSNull(),
            "extra_usage": [
                "is_enabled": true,
                "monthly_limit": 100.0,
                "used_credits": 19.0,
                "utilization": 19.0,
            ],
        ]

        let snapshot = AgentUsageParser.parseClaude(json, fetchedAt: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(snapshot.agent, .claude)
        XCTAssertEqual(snapshot.fiveHour?.usedPercent, 47)
        XCTAssertEqual(snapshot.fiveHour?.remainingPercent, 53)
        XCTAssertEqual(snapshot.sevenDay?.usedPercent, 30)
        XCTAssertEqual(snapshot.extra?.usedPercent, 19)
        XCTAssertEqual(snapshot.tightestWindow?.usedPercent, 47)
        XCTAssertNotNil(snapshot.fiveHour?.resetsAt)
        XCTAssertNotNil(snapshot.sevenDay?.resetsAt)
        XCTAssertEqual(AgentUsageParser.idleHint(from: snapshot)?.remainingPercent, 53)
        XCTAssertEqual(AgentUsageParser.idleHint(from: snapshot)?.tightness, .normal)
    }

    func testClaudeNullWindowsAreSkipped() {
        let json: [String: Any] = [
            "five_hour": NSNull(),
            "seven_day": [
                "utilization": 96.0,
                "resets_at": "2026-08-25T00:00:00Z",
            ],
            "extra_usage": [
                "is_enabled": false,
            ],
        ]
        let snapshot = AgentUsageParser.parseClaude(json)
        XCTAssertNil(snapshot.fiveHour)
        XCTAssertNil(snapshot.extra)
        XCTAssertEqual(snapshot.sevenDay?.tightness, .critical)
        XCTAssertEqual(AgentUsageParser.idleHint(from: snapshot)?.remainingPercent, 4)
    }

    func testCodexClassifiesWindowsByDuration() {
        let json: [String: Any] = [
            "plan_type": "plus",
            "rate_limit": [
                "primary_window": [
                    "used_percent": 55,
                    "limit_window_seconds": 18000,
                    "reset_at": 1_778_670_307,
                ],
                "secondary_window": [
                    "used_percent": 12.4,
                    "limit_window_seconds": 604800,
                    "reset_after_seconds": 489405,
                ],
            ],
        ]
        let snapshot = AgentUsageParser.parseCodex(json)
        XCTAssertEqual(snapshot.agent, .codex)
        XCTAssertEqual(snapshot.planName, "plus")
        XCTAssertEqual(snapshot.fiveHour?.usedPercent, 55)
        XCTAssertEqual(snapshot.sevenDay?.usedPercent, 12.4, accuracy: 0.01)
        XCTAssertEqual(snapshot.fiveHour?.remainingPercent, 45)
        XCTAssertNotNil(snapshot.fiveHour?.resetsAt)
        XCTAssertNotNil(snapshot.sevenDay?.resetsAt)
        XCTAssertEqual(AgentUsageParser.idleHint(from: snapshot)?.remainingPercent, 45)
        XCTAssertEqual(AgentUsageParser.idleHint(from: snapshot)?.tightness, .normal)
    }

    func testCodexSwappedSlotsStillMapByDuration() {
        let json: [String: Any] = [
            "rate_limit": [
                "primary_window": [
                    "used_percent": 8,
                    "limit_window_seconds": 604800,
                    "reset_at": 1_783_357_722,
                ],
                "secondary_window": [
                    "used_percent": 81,
                    "limit_window_seconds": 18000,
                    "reset_at": 1_778_670_307,
                ],
            ],
        ]
        let snapshot = AgentUsageParser.parseCodex(json)
        XCTAssertEqual(snapshot.fiveHour?.usedPercent, 81)
        XCTAssertEqual(snapshot.sevenDay?.usedPercent, 8)
        XCTAssertEqual(snapshot.fiveHour?.tightness, .warning)
        XCTAssertEqual(AgentUsageParser.idleHint(from: snapshot)?.remainingPercent, 19)
    }

    func testPercentCoercionClampsAndAcceptsInts() {
        XCTAssertEqual(AgentUsageParser.coercePercent(120), 100)
        XCTAssertEqual(AgentUsageParser.coercePercent(-4), 0)
        XCTAssertEqual(AgentUsageParser.coercePercent("33.5"), 33.5)
        XCTAssertNil(AgentUsageParser.coercePercent("nope"))
    }

    func testClaudeCredentialsParsing() {
        let json = """
        {"claudeAiOauth":{"accessToken":"sk-ant-oat01-test","subscriptionType":"max","rateLimitTier":"default_claude_max_5x"}}
        """.data(using: .utf8)!
        let parsed = AgentUsageClient.parseClaudeCredentialFile(json)
        XCTAssertEqual(parsed?.accessToken, "sk-ant-oat01-test")
        XCTAssertEqual(parsed?.planName, "Max 5×")
    }

    func testCodexAuthParsing() {
        let json = """
        {"tokens":{"access_token":"eyJtest","account_id":"user-123"}}
        """.data(using: .utf8)!
        let parsed = AgentUsageClient.parseCodexAuthFile(json)
        XCTAssertEqual(parsed?.accessToken, "eyJtest")
        XCTAssertEqual(parsed?.accountID, "user-123")
    }
}
