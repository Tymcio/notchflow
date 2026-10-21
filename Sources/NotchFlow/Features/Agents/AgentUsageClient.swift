import Foundation
import LocalAuthentication
import Security

/// Reads the Claude Code / Codex login already on this Mac and asks the provider
/// for 5-hour / 7-day usage. Tokens stay in memory for the request only.
enum AgentUsageClient {
    private static let claudeUsageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let claudeBeta = "oauth-2025-04-20"
    private static let codexUsageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private static let claudeKeychainService = "Claude Code-credentials"

    enum FetchError: Error {
        case signedOut
        case needsKeychainAccess
        case loginExpired
        case rateLimited(retryAfter: TimeInterval?)
        case http(Int)
        case invalidResponse
    }

    static var hasClaudeCredentials: Bool {
        claudeCredentialData() != nil || ClaudeDesktopCredentials.hasCredentialMaterial
    }

    static func claudePlanName(subscriptionType: String?, rateLimitTier: String?) -> String? {
        formatClaudePlan(subscriptionType: subscriptionType, rateLimitTier: rateLimitTier)
    }

    static var hasCodexCredentials: Bool {
        (try? loadCodexCredentials()) != nil
    }

    static func fetchClaude(allowKeychainPrompt: Bool = false) async throws -> AgentUsageSnapshot {
        if let creds = loadCLIClaudeCredentials() {
            do {
                return try await requestClaudeUsage(creds, source: "cli")
            } catch FetchError.signedOut {
                NotchFlowLog.agents.info("Claude CLI usage unauthorized, trying Desktop login")
            }
        }

        let desktop: ClaudeDesktopCredentials.Login
        do {
            desktop = try ClaudeDesktopCredentials.load(allowKeychainPrompt: allowKeychainPrompt)
        } catch let error as ClaudeDesktopCredentials.LoadError {
            switch error {
            case .needsKeychainAccess:
                throw FetchError.needsKeychainAccess
            case .expired:
                throw FetchError.loginExpired
            case .notFound:
                throw FetchError.signedOut
            case .unreadable:
                throw FetchError.invalidResponse
            }
        } catch {
            throw FetchError.invalidResponse
        }

        do {
            return try await requestClaudeUsage(
                ClaudeCredentials(accessToken: desktop.accessToken, planName: desktop.planName, expiresAt: nil),
                source: "desktop"
            )
        } catch FetchError.signedOut {
            throw FetchError.loginExpired
        }
    }

    private static func requestClaudeUsage(_ creds: ClaudeCredentials, source: String) async throws -> AgentUsageSnapshot {
        var request = URLRequest(url: claudeUsageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(claudeBeta, forHTTPHeaderField: "anthropic-beta")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let json = try await perform(request, provider: "Claude")
        var snapshot = AgentUsageParser.parseClaude(json)
        snapshot.planName = creds.planName
        snapshot.status = snapshot.hasMeters ? .ready : .unavailable
        let fiveHour = snapshot.fiveHour.map { Int($0.remainingPercent.rounded()) } ?? -1
        let sevenDay = snapshot.sevenDay.map { Int($0.remainingPercent.rounded()) } ?? -1
        NotchFlowLog.agents.info("Claude usage source=\(source, privacy: .public) 5hLeft=\(fiveHour, privacy: .public) 7dLeft=\(sevenDay, privacy: .public)")
        return snapshot
    }

    static func fetchCodex() async throws -> AgentUsageSnapshot {
        let creds = try loadCodexCredentials()
        var request = URLRequest(url: codexUsageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let accountID = creds.accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let json = try await perform(request, provider: "Codex")
        var snapshot = AgentUsageParser.parseCodex(json)
        if snapshot.planName == nil { snapshot.planName = creds.planName }
        snapshot.status = snapshot.hasMeters ? .ready : .unavailable
        return snapshot
    }

    private static func perform(_ request: URLRequest, provider: String) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FetchError.invalidResponse
        }
        switch http.statusCode {
        case 200..<300:
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw FetchError.invalidResponse
            }
            return json
        case 401, 403:
            NotchFlowLog.agents.info("\(provider, privacy: .public) usage unauthorized (\(http.statusCode, privacy: .public))")
            throw FetchError.signedOut
        case 429:
            let retryAfter = parseRetryAfter(http.value(forHTTPHeaderField: "Retry-After"))
            NotchFlowLog.agents.info("\(provider, privacy: .public) usage rate-limited")
            throw FetchError.rateLimited(retryAfter: retryAfter)
        default:
            NotchFlowLog.agents.info("\(provider, privacy: .public) usage HTTP \(http.statusCode, privacy: .public)")
            throw FetchError.http(http.statusCode)
        }
    }

    private static var userAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return "NotchFlow/\(version)"
    }

    private static func parseRetryAfter(_ raw: String?) -> TimeInterval? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if let seconds = TimeInterval(raw) {
            return max(seconds, 0)
        }
        return nil
    }

    // MARK: - Claude credentials

    private struct ClaudeCredentials {
        let accessToken: String
        let planName: String?
        let expiresAt: Date?
    }

    private static func loadCLIClaudeCredentials() -> ClaudeCredentials? {
        guard let data = claudeCredentialData(),
              let creds = decodeClaudeCredentials(data) else {
            return nil
        }
        if let expiresAt = creds.expiresAt, expiresAt <= Date() {
            return nil
        }
        return creds
    }

    private static func claudeCredentialData() -> Data? {
        if let data = claudeCredentialsFileData() { return data }
        return claudeKeychainData(allowPrompt: false)
    }

    private static func claudeCredentialsFileData() -> Data? {
        let override = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]
        let base: URL
        if let override, !override.isEmpty {
            base = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        }
        let url = base.appendingPathComponent(".credentials.json")
        return try? Data(contentsOf: url)
    }

    private static func claudeKeychainData(allowPrompt: Bool) -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: claudeKeychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        if !allowPrompt {
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = context
        }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return data
    }

    static func parseClaudeCredentialFile(_ data: Data) -> (accessToken: String, planName: String?)? {
        guard let creds = decodeClaudeCredentials(data) else { return nil }
        return (creds.accessToken, creds.planName)
    }

    private static func decodeClaudeCredentials(_ data: Data) -> ClaudeCredentials? {
        guard let root = jsonObject(from: data) else { return nil }
        let oauth = root["claudeAiOauth"] as? [String: Any] ?? root
        guard let token = oauth["accessToken"] as? String ?? oauth["access_token"] as? String,
              !token.isEmpty else {
            return nil
        }
        return ClaudeCredentials(
            accessToken: token,
            planName: formatClaudePlan(
                subscriptionType: oauth["subscriptionType"] as? String,
                rateLimitTier: oauth["rateLimitTier"] as? String
            ),
            expiresAt: AgentUsageParser.parseResetDate(oauth["expiresAt"])
        )
    }

    private static func jsonObject(from data: Data) -> [String: Any]? {
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return root
        }
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              let decoded = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: decoded) as? [String: Any] else {
            return nil
        }
        return root
    }

    private static func formatClaudePlan(subscriptionType: String?, rateLimitTier: String?) -> String? {
        guard let raw = subscriptionType?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let name = raw.replacingOccurrences(of: "_", with: " ").capitalized
        if let tier = rateLimitTier,
           let match = tier.range(of: #"\d+x"#, options: .regularExpression) {
            return "\(name) \(tier[match].dropLast())×"
        }
        return name
    }

    // MARK: - Codex credentials

    private struct CodexCredentials {
        let accessToken: String
        let accountID: String?
        let planName: String?
    }

    private static func loadCodexCredentials() throws -> CodexCredentials {
        let override = ProcessInfo.processInfo.environment["CODEX_HOME"]
        let base: URL
        if let override, !override.isEmpty {
            base = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        }
        let url = base.appendingPathComponent("auth.json")
        guard let data = try? Data(contentsOf: url),
              let creds = parseCodexAuth(data) else {
            throw FetchError.signedOut
        }
        return creds
    }

    static func parseCodexAuthFile(_ data: Data) -> (accessToken: String, accountID: String?)? {
        guard let creds = parseCodexAuth(data) else { return nil }
        return (creds.accessToken, creds.accountID)
    }

    private static func parseCodexAuth(_ data: Data) -> CodexCredentials? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let tokens = root["tokens"] as? [String: Any] ?? root
        guard let token = tokens["access_token"] as? String ?? tokens["accessToken"] as? String,
              !token.isEmpty else {
            return nil
        }
        let account = tokens["account_id"] as? String
            ?? tokens["accountId"] as? String
            ?? root["account_id"] as? String
        return CodexCredentials(
            accessToken: token,
            accountID: account,
            planName: tokens["plan_type"] as? String ?? root["plan_type"] as? String
        )
    }
}
