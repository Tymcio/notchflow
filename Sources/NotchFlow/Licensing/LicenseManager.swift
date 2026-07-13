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

    var isPremium: Bool {
        tier == .annual || tier == .lifetime
    }

    static let free = LicenseStatus(tier: .free, key: nil, validatedAt: nil, expiresAt: nil)
}

enum LicenseValidationError: Error, LocalizedError {
    case invalidKey
    case networkFailure
    case activationLimitReached
    case expired

    var errorDescription: String? {
        switch self {
        case .invalidKey: "Klucz licencyjny jest nieprawidłowy."
        case .networkFailure: "Nie udało się połączyć z serwerem licencji. Sprawdź internet i spróbuj ponownie."
        case .activationLimitReached: "Osiągnięto limit aktywacji dla tego klucza (maks. 2 Maci)."
        case .expired: "Roczna licencja wygasła."
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
    }

    func refreshIfNeeded() async {
        if let cached = loadCachedStatus(), isWithinGracePeriod(cached) {
            status = cached
            return
        }

        guard let key = keychain.read(key: KeychainKey.licenseKey) else {
            status = .free
            return
        }

        do {
            let session = try await validateStoredSession(key: key)
            try persist(session: session)
            status = session.status
        } catch {
            NotchFlowLog.license.error("License refresh failed: \(error.localizedDescription, privacy: .public)")
            if let cached = loadCachedStatus(), isWithinGracePeriod(cached) {
                status = cached
            } else {
                status = .free
            }
        }
    }

    func activate(key: String) async throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = try await apiClient.activate(
            key: trimmed,
            instanceName: Host.current().localizedName ?? "Mac"
        )
        try keychain.save(key: KeychainKey.licenseKey, value: trimmed)
        try keychain.save(key: KeychainKey.activationID, value: session.activationID)
        try persist(session: session)
        status = session.status
    }

    func deactivate() throws {
        try keychain.delete(key: KeychainKey.licenseKey)
        try keychain.delete(key: KeychainKey.activationID)
        try keychain.delete(key: KeychainKey.licenseStatus)
        status = .free
    }

    var storedLicenseKey: String? {
        keychain.read(key: KeychainKey.licenseKey)
    }

    private func validateStoredSession(key: String) async throws -> PolarLicenseSession {
        if let activationID = keychain.read(key: KeychainKey.activationID) {
            do {
                return try await apiClient.validate(key: key, activationID: activationID)
            } catch LicenseValidationError.invalidKey {
                try? keychain.delete(key: KeychainKey.activationID)
            }
        }

        return try await apiClient.activate(
            key: key,
            instanceName: Host.current().localizedName ?? "Mac"
        )
    }

    private func persist(session: PolarLicenseSession) throws {
        try keychain.save(key: KeychainKey.activationID, value: session.activationID)
        let data = try JSONEncoder().encode(PersistedLicenseStatus(status: session.status))
        try keychain.save(key: KeychainKey.licenseStatus, data: data)
    }

    private func loadCachedStatus() -> LicenseStatus? {
        guard let data = keychain.readData(key: KeychainKey.licenseStatus),
              let persisted = try? JSONDecoder().decode(PersistedLicenseStatus.self, from: data) else {
            return nil
        }
        return persisted.toStatus()
    }

    private func isWithinGracePeriod(_ status: LicenseStatus) -> Bool {
        guard let validatedAt = status.validatedAt else { return false }
        let graceEnd = validatedAt.addingTimeInterval(TimeInterval(NotchFlowConstants.licenseGraceDays * 24 * 3600))
        if let expiresAt = status.expiresAt, expiresAt < Date() {
            return false
        }
        return Date() <= graceEnd
    }
}

private struct PersistedLicenseStatus: Codable {
    let tier: LicenseTier
    let key: String?
    let validatedAt: Date?
    let expiresAt: Date?

    init(status: LicenseStatus) {
        tier = status.tier
        key = status.key
        validatedAt = status.validatedAt
        expiresAt = status.expiresAt
    }

    func toStatus() -> LicenseStatus {
        LicenseStatus(tier: tier, key: key, validatedAt: validatedAt, expiresAt: expiresAt)
    }
}
