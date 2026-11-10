import Foundation

/// Codex CLI login from `~/.codex/auth.json` (or `$CODEX_HOME`).
enum CodexUsageProvider: AgentUsageProvider {
    typealias FetchError = AgentUsageClient.FetchError

    static let agent: AgentKind = .codex

    private static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    static var hasCredentials: Bool {
        (try? loadCredentials()) != nil
    }

    static func fetch(allowKeychainPrompt: Bool) async throws -> AgentUsageSnapshot {
        let creds = try loadCredentials()
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AgentUsageHTTP.userAgent, forHTTPHeaderField: "User-Agent")
        if let accountID = creds.accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let json = try await AgentUsageHTTP.perform(request, provider: "Codex")
        var snapshot = AgentUsageParser.parseCodex(json)
        if snapshot.planName == nil { snapshot.planName = creds.planName }
        snapshot.status = snapshot.hasMeters ? .ready : .unavailable
        return snapshot
    }

    private struct Credentials {
        let accessToken: String
        let accountID: String?
        let planName: String?
    }

    private static func loadCredentials() throws -> Credentials {
        let override = ProcessInfo.processInfo.environment["CODEX_HOME"]
        let base: URL
        if let override, !override.isEmpty {
            base = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        }
        let url = base.appendingPathComponent("auth.json")
        guard let data = try? Data(contentsOf: url),
              let creds = parseAuth(data) else {
            throw FetchError.signedOut
        }
        return creds
    }

    static func parseAuthFile(_ data: Data) -> (accessToken: String, accountID: String?)? {
        guard let creds = parseAuth(data) else { return nil }
        return (creds.accessToken, creds.accountID)
    }

    private static func parseAuth(_ data: Data) -> Credentials? {
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
        return Credentials(
            accessToken: token,
            accountID: account,
            planName: tokens["plan_type"] as? String ?? root["plan_type"] as? String
        )
    }
}
