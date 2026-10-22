import CommonCrypto
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
        XCTAssertEqual(snapshot.sevenDay?.usedPercent ?? -1, 12.4, accuracy: 0.01)
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

    func testResetCopyFormatsFiveHourAndWeeklyWindows() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let english = Locale(identifier: "en_US")
        let polish = Locale(identifier: "pl_PL")
        XCTAssertEqual(
            AgentUsageResetCopy.duration(until: now.addingTimeInterval(90 * 60), now: now, locale: english),
            "1 hr, 30 min"
        )
        XCTAssertEqual(
            AgentUsageResetCopy.duration(until: now.addingTimeInterval(3 * 86_400 + 5 * 3_600), now: now, locale: polish),
            "3 dni i 5 godz."
        )
        XCTAssertEqual(
            AgentUsageResetCopy.duration(until: now.addingTimeInterval(12 * 60), now: now, locale: english),
            "12 min"
        )
        XCTAssertNil(AgentUsageResetCopy.duration(until: now.addingTimeInterval(30), now: now, locale: english))
        XCTAssertNil(AgentUsageResetCopy.duration(until: now.addingTimeInterval(-10), now: now, locale: english))
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

    func testDesktopCachePrefersFullScopeProductionLogin() {
        let organization = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let production = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
        let selection = ClaudeDesktopCredentials.select(
            v2: [
                cacheKey(organization: organization, scopes: "user:profile"):
                    tokenEntry("stale-plan", expiresIn: 86_400, now: now),
                cacheKey(organization: organization, clientID: production, scopes: "user:profile user:inference"):
                    tokenEntry("current", expiresIn: 1_800, now: now, rateLimitTier: "default_claude_max_5x"),
            ],
            v1: nil,
            organization: organization,
            accountUUID: nil,
            now: now
        )
        guard case .available(let login) = selection else {
            return XCTFail("expected a desktop login")
        }
        XCTAssertEqual(login.accessToken, "current")
        XCTAssertEqual(login.planName, "Max 5×")
    }

    func testDesktopAccountScopedEntryReplacesLegacyAndExpiredIsReported() {
        let organization = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        let account = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let legacy = cacheKey(organization: organization)
        let scoped = ClaudeDesktopCredentials.select(
            v2: [
                "acct:\(account)|\(legacy)": tokenEntry("desktop", expiresIn: 3_600, now: now),
                legacy: tokenEntry("old", expiresIn: 9_000, now: now),
            ],
            v1: nil,
            organization: organization,
            accountUUID: account,
            now: now
        )
        guard case .available(let login) = scoped else {
            return XCTFail("expected the account-scoped token")
        }
        XCTAssertEqual(login.accessToken, "desktop")

        let expired = ClaudeDesktopCredentials.select(
            v2: [legacy: tokenEntry("gone", expiresIn: -1, now: now)],
            v1: nil,
            organization: organization,
            accountUUID: nil,
            now: now
        )
        XCTAssertEqual(expired, .expired)

        let tombstone = ClaudeDesktopCredentials.select(
            v2: [legacy: NSNull()],
            v1: [legacy: tokenEntry("resurrected", expiresIn: 3_600, now: now)],
            organization: organization,
            accountUUID: nil,
            now: now
        )
        XCTAssertEqual(tombstone, .notFound)
    }

    func testDesktopSafeStorageRoundTrip() throws {
        let password = "fixture-safe-storage-password"
        let key = try XCTUnwrap(ClaudeDesktopCredentials.deriveKey(password: password))
        let plaintext = Data(#"{"token":"secret"}"#.utf8)
        let encrypted = try sealDesktopValue(plaintext, key: key)
        XCTAssertEqual(ClaudeDesktopCredentials.decrypt(encrypted, key: key), plaintext)
        XCTAssertNil(ClaudeDesktopCredentials.decrypt(Data("v11bad".utf8), key: key))
    }

    private func cacheKey(
        organization: String,
        clientID: String = "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
        scopes: String = "user:profile user:inference"
    ) -> String {
        "\(clientID):\(organization):https://api.anthropic.com:\(scopes)"
    }

    private func tokenEntry(
        _ token: String,
        expiresIn seconds: TimeInterval,
        now: Date,
        rateLimitTier: String = "default"
    ) -> [String: Any] {
        [
            "token": token,
            "expiresAt": (now.timeIntervalSince1970 + seconds) * 1000,
            "subscriptionType": "max",
            "rateLimitTier": rateLimitTier,
        ]
    }

    private func sealDesktopValue(_ plaintext: Data, key: Data) throws -> Data {
        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        var output = Data(count: plaintext.count + kCCBlockSizeAES128)
        var outputLength = 0
        let capacity = output.count
        let status = output.withUnsafeMutableBytes { outputBytes in
            plaintext.withUnsafeBytes { plaintextBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCEncrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            plaintextBytes.baseAddress,
                            plaintext.count,
                            outputBytes.baseAddress,
                            capacity,
                            &outputLength
                        )
                    }
                }
            }
        }
        XCTAssertTrue(status == kCCSuccess)
        output.count = outputLength
        return Data("v10".utf8) + output
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
