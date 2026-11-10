import AppKit
import Foundation

enum LicenseTier: String, Codable, Sendable {
    case free
    case annual
    case lifetime
}

struct LicenseStatus: Equatable, Sendable {
    let tier: LicenseTier
    let key: String?
    let validatedAt: Date?
    let expiresAt: Date?
    let hasAgentsAddon: Bool
    let agentsKey: String?
    let agentsValidatedAt: Date?

    var isPremium: Bool {
        tier == .annual || tier == .lifetime
    }

    static let free = LicenseStatus(
        tier: .free,
        key: nil,
        validatedAt: nil,
        expiresAt: nil,
        hasAgentsAddon: false,
        agentsKey: nil,
        agentsValidatedAt: nil
    )
}

enum LicenseValidationError: Error, LocalizedError {
    case invalidKey
    case networkFailure
    case activationLimitReached
    case expired
    case cannotDeactivate

    var errorDescription: String? {
        switch self {
        case .invalidKey: loc("The license key is invalid.")
        case .networkFailure: loc("Could not connect to the license server. Check your internet connection and try again.")
        case .activationLimitReached: loc("Activation limit reached for this key (max. 2 Macs).")
        case .expired: loc("The annual license has expired.")
        case .cannotDeactivate: loc("Cannot deactivate this activation. Try again later or use the Polar portal (Purchases → Deactivate).")
        }
    }
}

protocol LicenseAPI: Sendable {
    func activate(key: String, instanceName: String) async throws -> PolarLicenseSession
    func validate(key: String, activationID: String) async throws -> PolarLicenseSession
    func deactivate(key: String, activationID: String) async throws
}

@MainActor
final class LicenseManager {
    var onStatusChange: ((LicenseStatus) -> Void)?

    private(set) var status: LicenseStatus = .free {
        didSet {
            guard status != oldValue else { return }
            onStatusChange?(status)
        }
    }

    private let storage: LicenseStorage
    private let apiClient: any LicenseAPI
    private let now: () -> Date

    private var isRefreshing = false
    private var retryTask: Task<Void, Never>?
    private var retryAttempt = 0
    private var wakeObserver: NSObjectProtocol?

    /// Cached validations older than this are re-checked in the background so the
    /// offline grace period always counts from a recent successful validation.
    static let revalidationInterval: TimeInterval = 24 * 3600

    /// A validation stamped further in the future than this (clock skew allowance) is not
    /// trusted: it would otherwise keep the grace period and staleness checks happy forever.
    static let futureValidationTolerance: TimeInterval = 24 * 3600

    private enum StorageKey {
        static let licenseKey = "license_key"
        static let activationID = "license_activation_id"
        static let licenseStatus = "license_status"
        static let agentsKey = "agents_license_key"
        static let agentsActivationID = "agents_activation_id"

        static let all = [licenseKey, activationID, licenseStatus, agentsKey, agentsActivationID]
    }

    init(
        storage: LicenseStorage? = nil,
        apiClient: any LicenseAPI = PolarLicenseClient(),
        now: @escaping () -> Date = Date.init
    ) {
        self.storage = storage ?? LicenseStorage(
            legacyKeychain: KeychainStore(service: "eu.notchflow.app.license"),
            legacyKeys: StorageKey.all
        )
        self.apiClient = apiClient
        self.now = now
    }

    /// Re-checks the license after the Mac wakes (the network may need a moment;
    /// transient failures are retried with backoff instead of dropping to free).
    func startObservingSystemEvents() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.retryAttempt = 0
                await self.refreshIfNeeded()
            }
        }
    }

    private enum ValidationOutcome {
        case valid(PolarLicenseSession)
        /// The server definitively rejected the key (revoked, expired, unknown).
        case revoked
        /// Offline, server error, activation limit — keep the last known status.
        case unavailable
    }

    func refreshIfNeeded(force: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let premiumKey = storage.read(key: StorageKey.licenseKey)
        let agentsKey = storage.read(key: StorageKey.agentsKey)

        guard premiumKey != nil || agentsKey != nil else {
            cancelRetry()
            status = .free
            return
        }

        let cached = loadCachedStatus()
        if let cached, isWithinGracePeriod(cached),
           cacheCovers(cached, premiumKey: premiumKey, agentsKey: agentsKey) {
            status = cached
            if !force, !isStale(cached) {
                return
            }
        }

        var premiumPart = LicenseStatus.free
        var agentsPart = LicenseStatus.free
        var hadTransientFailure = false

        if let premiumKey {
            switch await validateStored(key: premiumKey, activationStorageKey: StorageKey.activationID) {
            case .valid(let session):
                if !session.isAgentsProduct {
                    try? persistPremium(session: session, key: premiumKey)
                    premiumPart = session.status
                }
            case .revoked:
                break
            case .unavailable:
                hadTransientFailure = true
                if let cached, cached.isPremium, isPremiumWithinGrace(cached) {
                    premiumPart = cached.premiumPart
                }
            }
        }

        if let agentsKey {
            switch await validateStored(key: agentsKey, activationStorageKey: StorageKey.agentsActivationID) {
            case .valid(let session):
                if session.isAgentsKey(agentsKey) {
                    try? persistAgents(session: session, key: agentsKey)
                    agentsPart = session.status.withAgentsAddon(key: agentsKey, validatedAt: now())
                }
            case .revoked:
                break
            case .unavailable:
                hadTransientFailure = true
                if let cached, cached.hasAgentsAddon, isAgentsWithinGrace(cached) {
                    agentsPart = cached.agentsPart
                }
            }
        }

        let next = merge(premium: premiumPart, agents: agentsPart)
        status = next
        try? persistCombinedStatus(next)

        if hadTransientFailure {
            scheduleRetry()
        } else {
            cancelRetry()
        }
    }

    private func validateStored(key: String, activationStorageKey: String) async -> ValidationOutcome {
        do {
            return .valid(try await validateStoredSession(key: key, activationStorageKey: activationStorageKey))
        } catch LicenseValidationError.invalidKey {
            NotchFlowLog.license.error("Stored license was rejected by the server")
            return .revoked
        } catch LicenseValidationError.expired {
            NotchFlowLog.license.error("Stored license has expired")
            return .revoked
        } catch {
            NotchFlowLog.license.error("License refresh unavailable: \(error.localizedDescription, privacy: .public)")
            return .unavailable
        }
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        let delay = min(30 * pow(2, Double(retryAttempt)), 15 * 60)
        retryAttempt += 1
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.refreshIfNeeded(force: true)
        }
    }

    private func cancelRetry() {
        retryTask?.cancel()
        retryTask = nil
        retryAttempt = 0
    }

    func activate(key: String) async throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = try await apiClient.activate(
            key: trimmed,
            instanceName: Host.current().localizedName ?? "Mac"
        )

        if session.isAgentsKey(trimmed) {
            try storage.save(key: StorageKey.agentsKey, value: trimmed)
            try storage.save(key: StorageKey.agentsActivationID, value: session.activationID)
            let agentsStatus = session.status.withAgentsAddon(key: trimmed, validatedAt: now())
            let merged = merge(premium: status, agents: agentsStatus)
            try persistCombinedStatus(merged)
            status = merged
            return
        }

        try storage.save(key: StorageKey.licenseKey, value: trimmed)
        try storage.save(key: StorageKey.activationID, value: session.activationID)
        let merged = merge(premium: session.status, agents: status)
        try persistCombinedStatus(merged)
        status = merged
    }

    func deactivate() throws {
        try storage.delete(key: StorageKey.licenseKey)
        try storage.delete(key: StorageKey.activationID)
        let agentsOnly = LicenseStatus(
            tier: .free,
            key: nil,
            validatedAt: nil,
            expiresAt: nil,
            hasAgentsAddon: status.hasAgentsAddon,
            agentsKey: status.agentsKey,
            agentsValidatedAt: status.agentsValidatedAt
        )
        try persistCombinedStatus(agentsOnly)
        status = agentsOnly
    }

    func deactivateAgents() throws {
        try storage.delete(key: StorageKey.agentsKey)
        try storage.delete(key: StorageKey.agentsActivationID)
        let premiumOnly = LicenseStatus(
            tier: status.tier,
            key: status.key,
            validatedAt: status.validatedAt,
            expiresAt: status.expiresAt,
            hasAgentsAddon: false,
            agentsKey: nil,
            agentsValidatedAt: nil
        )
        try persistCombinedStatus(premiumOnly)
        status = premiumOnly
    }

    func deactivateInPolar() async throws {
        guard let key = storage.read(key: StorageKey.licenseKey),
              let activationID = storage.read(key: StorageKey.activationID) else {
            throw LicenseValidationError.cannotDeactivate
        }

        do {
            try await apiClient.deactivate(key: key, activationID: activationID)
        } catch LicenseValidationError.invalidKey {
            // Treat "not found" as already deactivated / rotated; proceed with cleanup.
        } catch {
            throw LicenseValidationError.cannotDeactivate
        }

        try storage.delete(key: StorageKey.activationID)
        try deactivate()
    }

    func deactivateAgentsInPolar() async throws {
        guard let key = storage.read(key: StorageKey.agentsKey),
              let activationID = storage.read(key: StorageKey.agentsActivationID) else {
            throw LicenseValidationError.cannotDeactivate
        }

        do {
            try await apiClient.deactivate(key: key, activationID: activationID)
        } catch LicenseValidationError.invalidKey {
        } catch {
            throw LicenseValidationError.cannotDeactivate
        }

        try storage.delete(key: StorageKey.agentsActivationID)
        try deactivateAgents()
    }

    var storedLicenseKey: String? {
        storage.read(key: StorageKey.licenseKey)
    }

    var storedAgentsLicenseKey: String? {
        storage.read(key: StorageKey.agentsKey)
    }

    private func validateStoredSession(key: String, activationStorageKey: String) async throws -> PolarLicenseSession {
        if let activationID = storage.read(key: activationStorageKey) {
            do {
                return try await apiClient.validate(key: key, activationID: activationID)
            } catch LicenseValidationError.invalidKey {
                try? storage.delete(key: activationStorageKey)
            }
        }

        return try await apiClient.activate(
            key: key,
            instanceName: Host.current().localizedName ?? "Mac"
        )
    }

    private func persistPremium(session: PolarLicenseSession, key: String) throws {
        try storage.save(key: StorageKey.licenseKey, value: key)
        try storage.save(key: StorageKey.activationID, value: session.activationID)
    }

    private func persistAgents(session: PolarLicenseSession, key: String) throws {
        try storage.save(key: StorageKey.agentsKey, value: key)
        try storage.save(key: StorageKey.agentsActivationID, value: session.activationID)
    }

    private func persistCombinedStatus(_ status: LicenseStatus) throws {
        let data = try JSONEncoder().encode(PersistedLicenseStatus(status: status))
        try storage.save(key: StorageKey.licenseStatus, data: data)
    }

    private func loadCachedStatus() -> LicenseStatus? {
        guard let data = storage.readData(key: StorageKey.licenseStatus),
              let persisted = try? JSONDecoder().decode(PersistedLicenseStatus.self, from: data) else {
            return nil
        }
        return persisted.toStatus(
            key: storage.read(key: StorageKey.licenseKey),
            agentsKey: storage.read(key: StorageKey.agentsKey)
        )
    }

    private func merge(premium: LicenseStatus, agents: LicenseStatus) -> LicenseStatus {
        LicenseStatus(
            tier: premium.tier != .free ? premium.tier : .free,
            key: premium.key,
            validatedAt: premium.validatedAt,
            expiresAt: premium.expiresAt,
            hasAgentsAddon: agents.hasAgentsAddon || premium.hasAgentsAddon,
            agentsKey: agents.agentsKey ?? premium.agentsKey,
            agentsValidatedAt: agents.agentsValidatedAt ?? premium.agentsValidatedAt
        )
    }

    private func isWithinGracePeriod(_ status: LicenseStatus) -> Bool {
        let premiumOK = status.tier == .free || isPremiumWithinGrace(status)
        let agentsOK = !status.hasAgentsAddon || isAgentsWithinGrace(status)
        return premiumOK && agentsOK
    }

    private func isTrustworthy(_ validatedAt: Date) -> Bool {
        validatedAt <= now().addingTimeInterval(Self.futureValidationTolerance)
    }

    private func isPremiumWithinGrace(_ status: LicenseStatus) -> Bool {
        guard let validatedAt = status.validatedAt, isTrustworthy(validatedAt) else { return false }
        if let expiresAt = status.expiresAt, expiresAt < now() {
            return false
        }
        return now() <= validatedAt.addingTimeInterval(Self.gracePeriod)
    }

    private func isAgentsWithinGrace(_ status: LicenseStatus) -> Bool {
        guard let validatedAt = status.agentsValidatedAt ?? status.validatedAt,
              isTrustworthy(validatedAt) else { return false }
        return now() <= validatedAt.addingTimeInterval(Self.gracePeriod)
    }

    private static var gracePeriod: TimeInterval {
        TimeInterval(NotchFlowConstants.licenseGraceDays * 24 * 3600)
    }

    /// A cached status only stands in for validation when it accounts for every stored
    /// key — a cached "free" must never hide a key that has not been validated yet.
    private func cacheCovers(_ status: LicenseStatus, premiumKey: String?, agentsKey: String?) -> Bool {
        if premiumKey != nil, !status.isPremium { return false }
        if agentsKey != nil, !status.hasAgentsAddon { return false }
        return true
    }

    private func isStale(_ status: LicenseStatus) -> Bool {
        let dates = [
            status.isPremium ? status.validatedAt : nil,
            status.hasAgentsAddon ? (status.agentsValidatedAt ?? status.validatedAt) : nil,
        ].compactMap { $0 }
        guard let oldest = dates.min() else { return true }
        if dates.contains(where: { !isTrustworthy($0) }) { return true }
        return now().timeIntervalSince(oldest) > Self.revalidationInterval
    }
}

private extension LicenseStatus {
    func withAgentsAddon(key: String, validatedAt: Date) -> LicenseStatus {
        LicenseStatus(
            tier: .free,
            key: nil,
            validatedAt: nil,
            expiresAt: nil,
            hasAgentsAddon: true,
            agentsKey: key,
            agentsValidatedAt: validatedAt
        )
    }

    var premiumPart: LicenseStatus {
        LicenseStatus(
            tier: tier,
            key: key,
            validatedAt: validatedAt,
            expiresAt: expiresAt,
            hasAgentsAddon: false,
            agentsKey: nil,
            agentsValidatedAt: nil
        )
    }

    var agentsPart: LicenseStatus {
        LicenseStatus(
            tier: .free,
            key: nil,
            validatedAt: nil,
            expiresAt: nil,
            hasAgentsAddon: hasAgentsAddon,
            agentsKey: agentsKey,
            agentsValidatedAt: agentsValidatedAt ?? validatedAt
        )
    }
}

private struct PersistedLicenseStatus: Codable {
    let tier: LicenseTier
    let validatedAt: Date?
    let expiresAt: Date?
    let hasAgentsAddon: Bool?
    let agentsValidatedAt: Date?

    init(status: LicenseStatus) {
        tier = status.tier
        validatedAt = status.validatedAt
        expiresAt = status.expiresAt
        hasAgentsAddon = status.hasAgentsAddon
        agentsValidatedAt = status.agentsValidatedAt
    }

    func toStatus(key: String?, agentsKey: String?) -> LicenseStatus {
        LicenseStatus(
            tier: tier,
            key: key,
            validatedAt: validatedAt,
            expiresAt: expiresAt,
            hasAgentsAddon: hasAgentsAddon ?? false,
            agentsKey: agentsKey,
            agentsValidatedAt: agentsValidatedAt
        )
    }
}
