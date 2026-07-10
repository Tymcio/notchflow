import Foundation

struct LemonSqueezyLicenseClient {
    private let baseURL = URL(string: "https://api.lemonsqueezy.com/v1/licenses")!
    private let storeID = ProcessInfo.processInfo.environment["LEMONSQUEEZY_STORE_ID"] ?? ""
    private let productID = ProcessInfo.processInfo.environment["LEMONSQUEEZY_PRODUCT_ID"] ?? ""

    func activate(key: String, instanceName: String) async throws -> LicenseStatus {
        try await request(action: "activate", key: key, instanceName: instanceName)
    }

    func validate(key: String, instanceName: String) async throws -> LicenseStatus {
        try await request(action: "validate", key: key, instanceName: instanceName)
    }

    private func request(action: String, key: String, instanceName: String) async throws -> LicenseStatus {
        var request = URLRequest(url: baseURL.appendingPathComponent(action))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "license_key": key,
            "instance_name": instanceName
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw LicenseValidationError.networkFailure
            }

            guard (200..<300).contains(http.statusCode) else {
                if http.statusCode == 404 {
                    throw LicenseValidationError.invalidKey
                }
                if http.statusCode == 422 {
                    throw LicenseValidationError.activationLimitReached
                }
                throw LicenseValidationError.networkFailure
            }

            return try parseResponse(data: data, key: key)
        } catch let error as LicenseValidationError {
            throw error
        } catch {
            throw LicenseValidationError.networkFailure
        }
    }

    private func parseResponse(data: Data, key: String) throws -> LicenseStatus {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let license = json?["license_key"] as? [String: Any]
        let meta = json?["meta"] as? [String: Any]

        let status = (license?["status"] as? String) ?? (meta?["status"] as? String) ?? "invalid"
        guard status == "active" else {
            if status == "expired" {
                throw LicenseValidationError.expired
            }
            throw LicenseValidationError.invalidKey
        }

        let expiresAt = parseDate(license?["expires_at"] as? String)
        let tier: LicenseTier
        if expiresAt == nil {
            tier = .lifetime
        } else {
            tier = .annual
        }

        if let expiresAt, expiresAt < Date() {
            throw LicenseValidationError.expired
        }

        return LicenseStatus(
            tier: tier,
            key: key,
            validatedAt: Date(),
            expiresAt: expiresAt
        )
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: value)
    }
}
