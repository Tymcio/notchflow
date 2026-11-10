import Foundation

/// `grok login` bearer from `~/.grok/auth.json` (or `$GROK_HOME`).
enum GrokBuildUsageProvider: AgentUsageProvider {
    typealias FetchError = AgentUsageClient.FetchError

    static let agent: AgentKind = .grok

    static var hasCredentials: Bool {
        switch login() {
        case .missing: false
        case .ready, .expired: true
        }
    }

    static func fetch(allowKeychainPrompt: Bool) async throws -> AgentUsageSnapshot {
        let token: String
        switch login() {
        case .missing:
            throw FetchError.signedOut
        case .expired:
            throw FetchError.loginExpired
        case .ready(let key):
            token = key
        }
        guard let url = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits") else {
            throw FetchError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("xai-grok-cli", forHTTPHeaderField: "X-XAI-Token-Auth")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AgentUsageHTTP.userAgent, forHTTPHeaderField: "User-Agent")
        let json: [String: Any]
        do {
            json = try await AgentUsageHTTP.perform(request, provider: "Grok Build")
        } catch FetchError.signedOut {
            throw FetchError.loginExpired
        }
        var snapshot = AgentUsageParser.parseGrokBuild(json)
        snapshot.status = snapshot.hasMeters ? .ready : .unavailable
        let left = snapshot.sevenDay.map { Int($0.remainingPercent.rounded()) } ?? -1
        NotchFlowLog.agents.info("Grok Build usage 7dLeft=\(left, privacy: .public)")
        return snapshot
    }

    // MARK: - Credentials

    private enum Login {
        case ready(String)
        case expired
        case missing
    }

    /// Picks the `grok login` bearer (`key`) from `~/.grok/auth.json`.
    /// OIDC entries beat bare keys. An expired-only file does not get sent.
    static func selectToken(_ root: [String: Any], now: Date = Date()) -> String? {
        switch classify(root, now: now) {
        case .ready(let token): token
        case .expired, .missing: nil
        }
    }

    static func loginState(_ root: [String: Any], now: Date = Date()) -> String {
        switch classify(root, now: now) {
        case .ready: "ready"
        case .expired: "expired"
        case .missing: "missing"
        }
    }

    private static func login(now: Date = Date()) -> Login {
        let override = ProcessInfo.processInfo.environment["GROK_HOME"]
        let base: URL
        if let override, !override.isEmpty {
            base = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok")
        }
        let url = base.appendingPathComponent("auth.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .missing
        }
        return classify(root, now: now)
    }

    private struct Candidate {
        var token: String
        var hasRefresh: Bool
        var expiresAt: Date?
        var prefersOIDC: Bool
    }

    private static func classify(_ root: [String: Any], now: Date) -> Login {
        let candidates = candidates(root)
        guard !candidates.isEmpty else { return .missing }
        let usable = candidates.filter { candidate in
            guard let expiresAt = candidate.expiresAt else { return true }
            return expiresAt.timeIntervalSince(now) > 2 * 60
        }
        guard let best = usable.max(by: isWorse) else { return .expired }
        return .ready(best.token)
    }

    private static func isWorse(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.hasRefresh != rhs.hasRefresh { return !lhs.hasRefresh }
        if lhs.prefersOIDC != rhs.prefersOIDC { return !lhs.prefersOIDC }
        let left = lhs.expiresAt ?? .distantPast
        let right = rhs.expiresAt ?? .distantPast
        return left < right
    }

    private static func candidates(_ root: [String: Any]) -> [Candidate] {
        if let direct = candidate(root, label: "") {
            return [direct]
        }
        return root.compactMap { label, value in
            guard let object = value as? [String: Any] else { return nil }
            return candidate(object, label: label)
        }
    }

    private static func candidate(_ object: [String: Any], label: String) -> Candidate? {
        guard let token = (object["key"] as? String) ?? (object["access_token"] as? String) else { return nil }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("xai-") else { return nil }
        let refresh = (object["refresh_token"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Candidate(
            token: trimmed,
            hasRefresh: !refresh.isEmpty,
            expiresAt: AgentUsageParser.parseResetDate(object["expires_at"] ?? object["expiresAt"]),
            prefersOIDC: label.contains("auth.x.ai") || label.contains("accounts.x.ai")
        )
    }
}
