import Foundation

struct PolarLicenseClient {
    private let activateURL = URL(string: "https://api.polar.sh/v1/customer-portal/license-keys/activate")!
    private let validateURL = URL(string: "https://api.polar.sh/v1/customer-portal/license-keys/validate")!

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

    private func post(to url: URL, payload: [String: Any]) async throws -> Data {
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
            case 200..<300:
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

        let tier: LicenseTier = expiresAt == nil ? .lifetime : .annual

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
                key: key,
                validatedAt: Date(),
                expiresAt: expiresAt
            ),
            activationID: activationID
        )
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
}
