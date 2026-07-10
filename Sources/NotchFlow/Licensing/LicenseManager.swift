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
        case .invalidKey: "The license key is invalid."
        case .networkFailure: "Could not reach the license server."
        case .activationLimitReached: "Activation limit reached for this key."
        case .expired: "Your annual license has expired."
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
    private let apiClient = LemonSqueezyLicenseClient()

    func refreshIfNeeded() async {
        if let cached = loadCachedStatus(), isWithinGracePeriod(cached) {
            status = cached
            return
        }

        guard let key = keychain.read(key: "license_key") else {
            status = .free
            return
        }

        do {
            let validated = try await apiClient.validate(key: key, instanceName: Host.current().localizedName ?? "Mac")
            try persist(status: validated)
            status = validated
        } catch {
            if let cached = loadCachedStatus(), isWithinGracePeriod(cached) {
                status = cached
            } else {
                status = .free
            }
        }
    }

    func activate(key: String) async throws {
        let validated = try await apiClient.activate(key: key, instanceName: Host.current().localizedName ?? "Mac")
        try keychain.save(key: "license_key", value: key)
        try persist(status: validated)
        status = validated
    }

    func deactivate() throws {
        try keychain.delete(key: "license_key")
        try keychain.delete(key: "license_status")
        status = .free
    }

    private func persist(status: LicenseStatus) throws {
        let data = try JSONEncoder().encode(PersistedLicenseStatus(status: status))
        try keychain.save(key: "license_status", data: data)
    }

    private func loadCachedStatus() -> LicenseStatus? {
        guard let data = keychain.readData(key: "license_status"),
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

import AppKit
