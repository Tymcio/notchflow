import XCTest
@testable import NotchFlow

private final class FakeLicenseAPI: LicenseAPI, @unchecked Sendable {
    enum Mode {
        case granted
        case offline
        case revoked
    }

    var mode: Mode = .granted
    var now: Date = Date()
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
        switch mode {
        case .offline:
            throw LicenseValidationError.networkFailure
        case .revoked:
            throw LicenseValidationError.invalidKey
        case .granted:
            return PolarLicenseSession(
                status: LicenseStatus(
                    tier: .lifetime,
                    key: key,
                    validatedAt: now,
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
}

@MainActor
final class LicenseManagerTests: XCTestCase {
    private var directory: URL!
    private var api: FakeLicenseAPI!
    private var clock: Date!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchFlowLicenseTests-\(UUID().uuidString)", isDirectory: true)
        api = FakeLicenseAPI()
        clock = Date(timeIntervalSince1970: 1_800_000_000)
        api.now = clock
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

    private func advance(days: Double) {
        clock = clock.addingTimeInterval(days * 24 * 3600)
        api.now = clock
    }

    func testOfflineRefreshKeepsLicenseWithinGracePeriod() async throws {
        try await makeManager().activate(key: "PREMIUM-KEY")

        advance(days: 3)
        api.mode = .offline
        let relaunched = makeManager()
        await relaunched.refreshIfNeeded()

        XCTAssertEqual(relaunched.status.tier, .lifetime)
    }

    func testOfflineLaunchAfterGraceDoesNotStickToFree() async throws {
        try await makeManager().activate(key: "PREMIUM-KEY")

        advance(days: Double(NotchFlowConstants.licenseGraceDays + 1))
        api.mode = .offline
        let offline = makeManager()
        await offline.refreshIfNeeded()
        XCTAssertEqual(offline.status.tier, .free)

        // Network is back on the next launch: the stored key must be validated again
        // instead of trusting a cached "free" status.
        api.mode = .granted
        let online = makeManager()
        await online.refreshIfNeeded()
        XCTAssertEqual(online.status.tier, .lifetime)
    }

    func testCachedFreeStatusDoesNotHideStoredKey() async throws {
        try await makeManager().activate(key: "PREMIUM-KEY")
        advance(days: Double(NotchFlowConstants.licenseGraceDays + 1))
        api.mode = .offline
        await makeManager().refreshIfNeeded()

        api.mode = .granted
        let manager = makeManager()
        await manager.refreshIfNeeded()
        XCTAssertEqual(manager.status.tier, .lifetime)
    }

    func testFreshCacheSkipsNetwork() async throws {
        try await makeManager().activate(key: "PREMIUM-KEY")
        let callsAfterActivation = api.calls

        advance(days: 0.5)
        let manager = makeManager()
        await manager.refreshIfNeeded()

        XCTAssertEqual(manager.status.tier, .lifetime)
        XCTAssertEqual(api.calls, callsAfterActivation)
    }

    func testRevokedKeyFallsBackToFree() async throws {
        try await makeManager().activate(key: "PREMIUM-KEY")

        advance(days: 2)
        api.mode = .revoked
        let manager = makeManager()
        await manager.refreshIfNeeded()

        XCTAssertEqual(manager.status.tier, .free)
    }

    func testStorageRoundTripAndPermissions() throws {
        let url = directory.appendingPathComponent("storage.json")
        let storage = LicenseStorage(fileURL: url)
        try storage.save(key: "license_key", value: "abc")
        XCTAssertEqual(LicenseStorage(fileURL: url).read(key: "license_key"), "abc")

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)

        try storage.delete(key: "license_key")
        XCTAssertNil(storage.read(key: "license_key"))
    }
}
