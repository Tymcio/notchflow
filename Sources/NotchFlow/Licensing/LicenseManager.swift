import Foundation
import Security

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

@MainActor
final class LicenseManager {
    var onStatusChange: ((LicenseStatus) -> Void)?

    private(set) var status: LicenseStatus = .free {
        didSet { onStatusChange?(status) }
    }

    private let keychain = KeychainStore(service: "eu.notchflow.app.license")
    private let apiClient = PolarLicenseClient()

    private enum KeychainKey {
        static let licenseKey = "license_key"
        static let activationID = "license_activation_id"
        static let licenseStatus = "license_status"
        static let agentsKey = "agents_license_key"
        static let agentsActivationID = "agents_activation_id"
    }

    func refreshIfNeeded() async {
        if let cached = loadCachedStatus(), isWithinGracePeriod(cached) {
            status = cached
            return
        }

        var next = LicenseStatus.free

        if let key = keychain.read(key: KeychainKey.licenseKey) {
            do {
                let session = try await validateStoredSession(
                    key: key,
                    activationKeychainKey: KeychainKey.activationID
                )
                if !session.isAgentsProduct {
                    try persistPremium(session: session, key: key)
                    next = merge(premium: session.status, agents: next)
                }
            } catch {
                NotchFlowLog.license.error("License refresh failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        if let agentsKey = keychain.read(key: KeychainKey.agentsKey) {
            do {
                let session = try await validateStoredSession(
                    key: agentsKey,
                    activationKeychainKey: KeychainKey.agentsActivationID
                )
                if session.isAgentsProduct || PolarLicenseClient.looksLikeAgentsKey(agentsKey) {
                    try persistAgents(session: session, key: agentsKey)
                    next = merge(premium: next, agents: session.status.withAgentsAddon(key: agentsKey))
                }
            } catch {
                NotchFlowLog.license.error("Agents license refresh failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        if next == .free, let cached = loadCachedStatus(), isWithinGracePeriod(cached) {
            status = cached
        } else {
            status = next
            try? persistCombinedStatus(next)
        }
    }

    func activate(key: String) async throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = try await apiClient.activate(
            key: trimmed,
            instanceName: Host.current().localizedName ?? "Mac"
        )

        if session.isAgentsProduct || PolarLicenseClient.looksLikeAgentsKey(trimmed) {
            try keychain.save(key: KeychainKey.agentsKey, value: trimmed)
            try keychain.save(key: KeychainKey.agentsActivationID, value: session.activationID)
            let agentsStatus = session.status.withAgentsAddon(key: trimmed)
            let merged = merge(premium: status, agents: agentsStatus)
            try persistCombinedStatus(merged)
            status = merged
            return
        }

        try keychain.save(key: KeychainKey.licenseKey, value: trimmed)
        try keychain.save(key: KeychainKey.activationID, value: session.activationID)
        let merged = merge(premium: session.status, agents: status)
        try persistCombinedStatus(merged)
        status = merged
    }

    func deactivate() throws {
        try keychain.delete(key: KeychainKey.licenseKey)
        try keychain.delete(key: KeychainKey.activationID)
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
        try keychain.delete(key: KeychainKey.agentsKey)
        try keychain.delete(key: KeychainKey.agentsActivationID)
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
        guard let key = keychain.read(key: KeychainKey.licenseKey),
              let activationID = keychain.read(key: KeychainKey.activationID) else {
            throw LicenseValidationError.cannotDeactivate
        }

        do {
            try await apiClient.deactivate(key: key, activationID: activationID)
        } catch LicenseValidationError.invalidKey {
            // Treat "not found" as already deactivated / rotated; proceed with cleanup.
        } catch {
            throw LicenseValidationError.cannotDeactivate
        }

        try keychain.delete(key: KeychainKey.activationID)
        try deactivate()
    }

    func deactivateAgentsInPolar() async throws {
        guard let key = keychain.read(key: KeychainKey.agentsKey),
              let activationID = keychain.read(key: KeychainKey.agentsActivationID) else {
            throw LicenseValidationError.cannotDeactivate
        }

        do {
            try await apiClient.deactivate(key: key, activationID: activationID)
        } catch LicenseValidationError.invalidKey {
        } catch {
            throw LicenseValidationError.cannotDeactivate
        }

        try keychain.delete(key: KeychainKey.agentsActivationID)
        try deactivateAgents()
    }

    var storedLicenseKey: String? {
        keychain.read(key: KeychainKey.licenseKey)
    }

    var storedAgentsLicenseKey: String? {
        keychain.read(key: KeychainKey.agentsKey)
    }

    private func validateStoredSession(key: String, activationKeychainKey: String) async throws -> PolarLicenseSession {
        if let activationID = keychain.read(key: activationKeychainKey) {
            do {
                return try await apiClient.validate(key: key, activationID: activationID)
            } catch LicenseValidationError.invalidKey {
                try? keychain.delete(key: activationKeychainKey)
            }
        }

        return try await apiClient.activate(
            key: key,
            instanceName: Host.current().localizedName ?? "Mac"
        )
    }

    private func persistPremium(session: PolarLicenseSession, key: String) throws {
        try keychain.save(key: KeychainKey.licenseKey, value: key)
        try keychain.save(key: KeychainKey.activationID, value: session.activationID)
    }

    private func persistAgents(session: PolarLicenseSession, key: String) throws {
        try keychain.save(key: KeychainKey.agentsKey, value: key)
        try keychain.save(key: KeychainKey.agentsActivationID, value: session.activationID)
    }

    private func persistCombinedStatus(_ status: LicenseStatus) throws {
        let data = try JSONEncoder().encode(PersistedLicenseStatus(status: status))
        try keychain.save(key: KeychainKey.licenseStatus, data: data)
    }

    private func loadCachedStatus() -> LicenseStatus? {
        guard let data = keychain.readData(key: KeychainKey.licenseStatus),
              let persisted = try? JSONDecoder().decode(PersistedLicenseStatus.self, from: data) else {
            return nil
        }
        return persisted.toStatus(
            key: keychain.read(key: KeychainKey.licenseKey),
            agentsKey: keychain.read(key: KeychainKey.agentsKey)
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
        let premiumOK: Bool = {
            guard status.tier != .free else { return true }
            guard let validatedAt = status.validatedAt else { return false }
            let graceEnd = validatedAt.addingTimeInterval(
                TimeInterval(NotchFlowConstants.licenseGraceDays * 24 * 3600)
            )
            if let expiresAt = status.expiresAt, expiresAt < Date() {
                return false
            }
            return Date() <= graceEnd
        }()

        let agentsOK: Bool = {
            guard status.hasAgentsAddon else { return true }
            guard let validatedAt = status.agentsValidatedAt ?? status.validatedAt else { return false }
            let graceEnd = validatedAt.addingTimeInterval(
                TimeInterval(NotchFlowConstants.licenseGraceDays * 24 * 3600)
            )
            return Date() <= graceEnd
        }()

        return premiumOK && agentsOK
    }
}

private extension LicenseStatus {
    func withAgentsAddon(key: String) -> LicenseStatus {
        LicenseStatus(
            tier: .free,
            key: nil,
            validatedAt: nil,
            expiresAt: nil,
            hasAgentsAddon: true,
            agentsKey: key,
            agentsValidatedAt: Date()
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
