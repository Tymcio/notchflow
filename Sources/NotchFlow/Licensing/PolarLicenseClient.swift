import Foundation

/// Polar benefit IDs that identify NotchFlow's products. They are injected into Info.plist
/// at packaging time (`POLAR_PREMIUM_BENEFIT_IDS`, `POLAR_AGENTS_BENEFIT_IDS`, comma-separated).
/// When none are configured, the product is guessed from the key prefix and product names.
struct PolarBenefitIDs: Equatable, Sendable {
    var premium: Set<String>
    var agents: Set<String>

    static let none = PolarBenefitIDs(premium: [], agents: [])

    var isConfigured: Bool { !premium.isEmpty || !agents.isEmpty }

    static func parse(_ raw: String?) -> Set<String> {
        guard let raw else { return [] }
        let separators = CharacterSet(charactersIn: ",;").union(.whitespacesAndNewlines)
        return Set(raw.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty })
    }

    static func fromBundle(_ bundle: Bundle = .main, environment: [String: String] = ProcessInfo.processInfo.environment) -> PolarBenefitIDs {
        func value(_ plistKey: String, _ envKey: String) -> Set<String> {
            let bundled = parse(bundle.object(forInfoDictionaryKey: plistKey) as? String)
            return bundled.isEmpty ? parse(environment[envKey]) : bundled
        }
        return PolarBenefitIDs(
            premium: value("PolarPremiumBenefitIDs", "POLAR_PREMIUM_BENEFIT_IDS"),
            agents: value("PolarAgentsBenefitIDs", "POLAR_AGENTS_BENEFIT_IDS")
        )
    }

    enum Product: Equatable {
        case premium
        case agents
    }

    /// The product a Polar `benefit_id` belongs to, or nil when it is not one of ours.
    /// With only one list configured, any other benefit counts as the other product.
    func product(forBenefitID raw: String?) -> Product? {
        let id = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if !id.isEmpty {
            if agents.contains(id) { return .agents }
            if premium.contains(id) { return .premium }
        }
        switch (premium.isEmpty, agents.isEmpty) {
        case (false, true): return id.isEmpty ? nil : .agents
        case (true, false): return id.isEmpty ? nil : .premium
        default: return nil
        }
    }
}

struct PolarLicenseClient: LicenseAPI {
    private let benefitIDs: PolarBenefitIDs

    init(benefitIDs: PolarBenefitIDs = .fromBundle()) {
        self.benefitIDs = benefitIDs
    }

    private let activateURL = URL(string: "https://api.polar.sh/v1/customer-portal/license-keys/activate")!
    private let validateURL = URL(string: "https://api.polar.sh/v1/customer-portal/license-keys/validate")!
    private let deactivateURL = URL(string: "https://api.polar.sh/v1/customer-portal/license-keys/deactivate")!

    /// Public Polar organization ID (not a secret). Used when the build did not inject
    /// `PolarOrganizationID` — e.g. local `compile_and_run.sh` builds — so license
    /// validation works the same as in release builds.
    static let defaultOrganizationID = "8a00b3a5-7845-4e8f-99b5-ae1ec8d49fca"

    private var organizationID: String {
        if let bundled = Bundle.main.object(forInfoDictionaryKey: "PolarOrganizationID") as? String,
           !bundled.isEmpty {
            return bundled
        }
        if let env = ProcessInfo.processInfo.environment["POLAR_ORGANIZATION_ID"], !env.isEmpty {
            return env
        }
        return Self.defaultOrganizationID
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
        return try Self.parseSession(json: json, key: key, benefitIDs: benefitIDs)
    }

    static func parseSession(
        json: [String: Any],
        key: String,
        benefitIDs: PolarBenefitIDs,
        now: Date = Date()
    ) throws -> PolarLicenseSession {

        let licenseObject = (json["license_key"] as? [String: Any]) ?? json
        guard let status = licenseObject["status"] as? String, status == "granted" else {
            throw LicenseValidationError.invalidKey
        }

        let expiresAt = parseDate(licenseObject["expires_at"] as? String)
        if let expiresAt, expiresAt < now {
            throw LicenseValidationError.expired
        }

        let isAgents: Bool
        if benefitIDs.isConfigured {
            // The benefit the key was issued for decides the product, not its name.
            let benefitID = (licenseObject["benefit_id"] as? String) ?? (json["benefit_id"] as? String)
            switch benefitIDs.product(forBenefitID: benefitID) {
            case .agents: isAgents = true
            case .premium: isAgents = false
            case nil:
                NotchFlowLog.license.error("License key belongs to an unknown Polar benefit")
                throw LicenseValidationError.invalidKey
            }
        } else {
            isAgents = detectAgentsProduct(key: key, licenseObject: licenseObject, root: json)
        }
        // Annual vs lifetime only changes the label; access is enforced by expiry and validation.
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
                validatedAt: isAgents ? nil : now,
                expiresAt: isAgents ? nil : expiresAt,
                hasAgentsAddon: isAgents,
                agentsKey: isAgents ? key : nil,
                agentsValidatedAt: isAgents ? now : nil
            ),
            activationID: activationID,
            isAgentsProduct: isAgents,
            productVerifiedByBenefit: benefitIDs.isConfigured
        )
    }

    /// Fallback guess used only when no benefit IDs are configured.
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

    private static func parseDate(_ value: String?) -> Date? {
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
    /// True when `isAgentsProduct` came from a configured Polar benefit ID rather than a guess.
    var productVerifiedByBenefit: Bool = false

    /// Whether `key` should be stored as the Agents addon key.
    func isAgentsKey(_ key: String) -> Bool {
        if productVerifiedByBenefit { return isAgentsProduct }
        return isAgentsProduct || PolarLicenseClient.looksLikeAgentsKey(key)
    }
}
