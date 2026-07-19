import Foundation

struct PolarLicenseClient {
    private let activateURL = URL(string: "https://api.polar.sh/v1/customer-portal/license-keys/activate")!
    private let validateURL = URL(string: "https://api.polar.sh/v1/customer-portal/license-keys/validate")!
    private let deactivateURL = URL(string: "https://api.polar.sh/v1/customer-portal/license-keys/deactivate")!

    private var organizationID: String {
        if let bundled = Bundle.main.object(forInfoDictionaryKey: "PolarOrganizationID") as? String,
           !bundled.isEmpty {
            return bundled
        }
        return ProcessInfo.processInfo.environment["POLAR_ORGANIZATION_ID"] ?? ""
    }

    func activate(key: String, instanceName: String) async throws -> PolarLicenseSession {
        guard !organizationID.isEmpty else {
            NotchFlowLog.license.error("Polar organization ID is not configured")
            throw LicenseValidationError.networkFailure
        }

        let payload: [String: Any] = [
            "key": key,
            "organization_id": organizationID,
            "label": instanceName,
        ]

        let data = try await post(to: activateURL, payload: payload)
        return try parseSession(data: data, key: key)
    }

    func validate(key: String, activationID: String) async throws -> PolarLicenseSession {
        guard !organizationID.isEmpty else {
            throw LicenseValidationError.networkFailure
        }

        let payload: [String: Any] = [
            "key": key,
            "organization_id": organizationID,
            "activation_id": activationID,
        ]

        let data = try await post(to: validateURL, payload: payload)
        return try parseSession(data: data, key: key)
    }

    func deactivate(key: String, activationID: String) async throws {
        guard !organizationID.isEmpty else {
            throw LicenseValidationError.networkFailure
        }

        let payload: [String: Any] = [
            "key": key,
            "organization_id": organizationID,
            "activation_id": activationID,
        ]

        _ = try await post(to: deactivateURL, payload: payload, expectedStatusCodes: 200..<300)
    }

    private func post(
        to url: URL,
        payload: [String: Any],
        expectedStatusCodes: Range<Int> = 200..<300
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw LicenseValidationError.networkFailure
            }

            switch http.statusCode {
            case expectedStatusCodes:
                return data
            case 404:
                throw LicenseValidationError.invalidKey
            case 403, 422:
                throw mapErrorPayload(data) ?? LicenseValidationError.activationLimitReached
            default:
                throw LicenseValidationError.networkFailure
            }
        } catch let error as LicenseValidationError {
            throw error
        } catch {
            throw LicenseValidationError.networkFailure
        }
    }

    private func mapErrorPayload(_ data: Data) -> LicenseValidationError? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let detail = (json["detail"] as? String)?.lowercased() ?? ""
        if detail.contains("activation") || detail.contains("limit") {
            return .activationLimitReached
        }
        if detail.contains("expired") {
            return .expired
        }
        return nil
    }

    private func parseSession(data: Data, key: String) throws -> PolarLicenseSession {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LicenseValidationError.networkFailure
        }

        let licenseObject = (json["license_key"] as? [String: Any]) ?? json
        guard let status = licenseObject["status"] as? String, status == "granted" else {
            throw LicenseValidationError.invalidKey
        }

        let expiresAt = parseDate(licenseObject["expires_at"] as? String)
        if let expiresAt, expiresAt < Date() {
            throw LicenseValidationError.expired
        }

        let isAgents = Self.detectAgentsProduct(key: key, licenseObject: licenseObject, root: json)
        let tier: LicenseTier = isAgents ? .free : (expiresAt == nil ? .lifetime : .annual)

        let activationID: String?
        if json["license_key"] != nil {
            activationID = json["id"] as? String
        } else {
            activationID = (json["activation"] as? [String: Any])?["id"] as? String
        }

        guard let activationID, !activationID.isEmpty else {
            throw LicenseValidationError.networkFailure
        }

        return PolarLicenseSession(
            status: LicenseStatus(
                tier: tier,
                key: isAgents ? nil : key,
                validatedAt: isAgents ? nil : Date(),
                expiresAt: isAgents ? nil : expiresAt,
                hasAgentsAddon: isAgents,
                agentsKey: isAgents ? key : nil,
                agentsValidatedAt: isAgents ? Date() : nil
            ),
            activationID: activationID,
            isAgentsProduct: isAgents
        )
    }

    static func looksLikeAgentsKey(_ key: String) -> Bool {
        let upper = key.uppercased()
        return upper.contains("AGENTS") || upper.contains("NOTCHFLOW_AGENT")
    }

    private static func detectAgentsProduct(key: String, licenseObject: [String: Any], root: [String: Any]) -> Bool {
        if looksLikeAgentsKey(key) { return true }

        if let meta = licenseObject["metadata"] as? [String: Any] {
            if let addon = (meta["addon"] as? String)?.lowercased(), addon.contains("agent") {
                return true
            }
            if let product = (meta["product"] as? String)?.lowercased(), product.contains("agent") {
                return true
            }
        }

        let nameCandidates: [String?] = [
            licenseObject["display_name"] as? String,
            licenseObject["name"] as? String,
            (root["benefit"] as? [String: Any])?["description"] as? String,
            (root["product"] as? [String: Any])?["name"] as? String,
        ]
        for name in nameCandidates.compactMap({ $0?.lowercased() }) {
            if name.contains("agent") { return true }
        }
        return false
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

struct PolarLicenseSession: Equatable, Sendable {
    let status: LicenseStatus
    let activationID: String
    let isAgentsProduct: Bool
}
