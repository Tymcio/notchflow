import XCTest
@testable import NotchFlow

private final class ClockedLicenseAPI: LicenseAPI, @unchecked Sendable {
    var offline = false
    /// The time the "server" stamps on a validation.
    var serverNow = Date()
    private(set) var calls = 0

    func activate(key: String, instanceName: String) async throws -> PolarLicenseSession {
        try respond(key: key)
    }

    func validate(key: String, activationID: String) async throws -> PolarLicenseSession {
        try respond(key: key)
    }

    func deactivate(key: String, activationID: String) async throws {}

    private func respond(key: String) throws -> PolarLicenseSession {
        calls += 1
        if offline { throw LicenseValidationError.networkFailure }
        return PolarLicenseSession(
            status: LicenseStatus(
                tier: .lifetime,
                key: key,
                validatedAt: serverNow,
                expiresAt: nil,
                hasAgentsAddon: false,
                agentsKey: nil,
                agentsValidatedAt: nil
            ),
            activationID: "activation-1",
            isAgentsProduct: false
        )
    }
}

@MainActor
final class LicenseFutureValidationTests: XCTestCase {
    private var directory: URL!
    private var api: ClockedLicenseAPI!
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchFlowLicenseTrust-\(UUID().uuidString)", isDirectory: true)
        api = ClockedLicenseAPI()
        api.serverNow = clock
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeManager() -> LicenseManager {
        LicenseManager(
            storage: LicenseStorage(fileURL: directory.appendingPathComponent("license.json")),
            apiClient: api,
            now: { [unowned self] in self.clock }
        )
    }

    /// A cache stamped far in the future (clock rolled back, or a hand-edited file).
    private func activateWithFutureStamp(days: Double) async throws {
        api.serverNow = clock.addingTimeInterval(days * 24 * 3600)
        try await makeManager().activate(key: "PREMIUM-KEY")
        api.serverNow = clock
    }

    func testFutureValidationIsRevalidatedInsteadOfTrusted() async throws {
        try await activateWithFutureStamp(days: 365)
        let callsAfterActivation = api.calls

        let manager = makeManager()
        await manager.refreshIfNeeded()

        XCTAssertEqual(api.calls, callsAfterActivation + 1, "a future-dated cache must not skip validation")
        XCTAssertEqual(manager.status.tier, .lifetime)
        XCTAssertEqual(manager.status.validatedAt, clock)
    }

    func testFutureValidationDoesNotGrantOfflineGrace() async throws {
        try await activateWithFutureStamp(days: 365)

        api.offline = true
        let manager = makeManager()
        await manager.refreshIfNeeded()

        XCTAssertEqual(manager.status.tier, .free)
    }

    func testSmallClockSkewIsTolerated() async throws {
        try await activateWithFutureStamp(days: 0.5)
        let callsAfterActivation = api.calls

        api.offline = true
        let manager = makeManager()
        await manager.refreshIfNeeded()

        XCTAssertEqual(manager.status.tier, .lifetime)
        XCTAssertEqual(api.calls, callsAfterActivation, "a fresh, slightly skewed stamp still counts as fresh")
    }
}

final class PolarBenefitIDTests: XCTestCase {
    private let premiumID = "11111111-1111-1111-1111-111111111111"
    private let agentsID = "22222222-2222-2222-2222-222222222222"

    private func validateResponse(benefitID: String?, expiresAt: String? = nil) -> [String: Any] {
        var json: [String: Any] = [
            "id": "license-1",
            "status": "granted",
            "display_name": "NotchFlow Agents addon",
            "activation": ["id": "activation-1"],
        ]
        if let benefitID { json["benefit_id"] = benefitID }
        if let expiresAt { json["expires_at"] = expiresAt }
        return json
    }

    func testParsesCommaSeparatedIDs() {
        XCTAssertEqual(PolarBenefitIDs.parse(" A, b ,,c\n"), ["a", "b", "c"])
        XCTAssertEqual(PolarBenefitIDs.parse(nil), [])
        XCTAssertFalse(PolarBenefitIDs.none.isConfigured)
    }

    func testBenefitIDDecidesTheProductOverNamesAndPrefixes() throws {
        let ids = PolarBenefitIDs(premium: [premiumID], agents: [agentsID])

        // Named like the addon and prefixed like an Agents key, but issued by the Premium benefit.
        let premium = try PolarLicenseClient.parseSession(
            json: validateResponse(benefitID: premiumID),
            key: "NOTCHFLOW_AGENTS_ABC",
            benefitIDs: ids
        )
        XCTAssertFalse(premium.isAgentsProduct)
        XCTAssertTrue(premium.productVerifiedByBenefit)
        XCTAssertFalse(premium.isAgentsKey("NOTCHFLOW_AGENTS_ABC"))
        XCTAssertTrue(premium.status.isPremium)

        let agents = try PolarLicenseClient.parseSession(
            json: validateResponse(benefitID: agentsID.uppercased()),
            key: "NOTCHFLOW_XYZ",
            benefitIDs: ids
        )
        XCTAssertTrue(agents.isAgentsProduct)
        XCTAssertTrue(agents.isAgentsKey("NOTCHFLOW_XYZ"))
        XCTAssertFalse(agents.status.isPremium)
    }

    func testUnknownBenefitIsRejectedWhenBothListsAreConfigured() {
        let ids = PolarBenefitIDs(premium: [premiumID], agents: [agentsID])
        XCTAssertThrowsError(try PolarLicenseClient.parseSession(
            json: validateResponse(benefitID: "33333333-3333-3333-3333-333333333333"),
            key: "NOTCHFLOW_X",
            benefitIDs: ids
        )) { error in
            XCTAssertEqual(error as? LicenseValidationError, .invalidKey)
        }
        XCTAssertThrowsError(try PolarLicenseClient.parseSession(
            json: validateResponse(benefitID: nil),
            key: "NOTCHFLOW_X",
            benefitIDs: ids
        ))
    }

    func testActivationResponseNestsTheBenefitInLicenseKey() throws {
        let ids = PolarBenefitIDs(premium: [premiumID], agents: [agentsID])
        let json: [String: Any] = [
            "id": "activation-9",
            "license_key": ["status": "granted", "benefit_id": agentsID],
        ]
        let session = try PolarLicenseClient.parseSession(json: json, key: "K", benefitIDs: ids)
        XCTAssertTrue(session.isAgentsProduct)
        XCTAssertEqual(session.activationID, "activation-9")
    }

    func testFallsBackToTheOldGuessWhenNothingIsConfigured() throws {
        let guessed = try PolarLicenseClient.parseSession(
            json: validateResponse(benefitID: premiumID),
            key: "NOTCHFLOW_X",
            benefitIDs: .none
        )
        XCTAssertTrue(guessed.isAgentsProduct, "display name mentions the addon")
        XCTAssertFalse(guessed.productVerifiedByBenefit)
    }

    func testOnlyOneListConfiguredTreatsOtherBenefitsAsTheOtherProduct() {
        let agentsOnly = PolarBenefitIDs(premium: [], agents: [agentsID])
        XCTAssertEqual(agentsOnly.product(forBenefitID: agentsID), .agents)
        XCTAssertEqual(agentsOnly.product(forBenefitID: premiumID), .premium)
        XCTAssertNil(agentsOnly.product(forBenefitID: nil))
    }
}
