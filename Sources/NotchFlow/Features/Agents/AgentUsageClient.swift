import CryptoKit
import Foundation
import LocalAuthentication
import Security
import SQLite3

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

    static var hasCursorCredentials: Bool {
        switch cursorLogin() {
        case .missing: false
        case .ready, .expired: true
        }
    }

    static func fetchCursor(allowKeychainPrompt: Bool = false) async throws -> AgentUsageSnapshot {
        do {
            return try await loadCursorUsage(allowKeychainPrompt: false)
        } catch FetchError.needsKeychainAccess {
            let shouldPrompt = allowKeychainPrompt || !didPromptForCursorKeychain
            guard shouldPrompt else { throw FetchError.needsKeychainAccess }
            didPromptForCursorKeychain = true
            return try await loadCursorUsage(allowKeychainPrompt: true)
        }
    }

    private static func loadCursorUsage(allowKeychainPrompt: Bool) async throws -> AgentUsageSnapshot {
        var token = try await cursorAccessToken(allowKeychainPrompt: allowKeychainPrompt)
        let usage: [String: Any]
        do {
            usage = try await postCursor("GetCurrentPeriodUsage", token: token)
        } catch FetchError.signedOut {
            guard let refreshed = try await refreshedCursorAccessToken(allowKeychainPrompt: allowKeychainPrompt) else {
                throw FetchError.loginExpired
            }
            token = refreshed
            do {
                usage = try await postCursor("GetCurrentPeriodUsage", token: token)
            } catch FetchError.signedOut {
                throw FetchError.loginExpired
            }
        }
        let plan = try? await postCursor("GetPlanInfo", token: token)
        var snapshot = AgentUsageParser.parseCursor(usage: usage, plan: plan)
        snapshot.status = snapshot.hasMeters ? .ready : .unavailable
        let summary = snapshot.meters
            .map { "\($0.label)=\(Int($0.window.remainingPercent.rounded()))" }
            .joined(separator: " ")
        NotchFlowLog.agents.info("Cursor usage \(summary, privacy: .public)")
        return snapshot
    }

    static var hasGrokBuildCredentials: Bool {
        switch grokBuildLogin() {
        case .missing: false
        case .ready, .expired: true
        }
    }

    static func fetchGrokBuild() async throws -> AgentUsageSnapshot {
        let token: String
        switch grokBuildLogin() {
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
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let json: [String: Any]
        do {
            json = try await perform(request, provider: "Grok Build")
        } catch FetchError.signedOut {
            throw FetchError.loginExpired
        }
        var snapshot = AgentUsageParser.parseGrokBuild(json)
        snapshot.status = snapshot.hasMeters ? .ready : .unavailable
        let left = snapshot.sevenDay.map { Int($0.remainingPercent.rounded()) } ?? -1
        NotchFlowLog.agents.info("Grok Build usage 7dLeft=\(left, privacy: .public)")
        return snapshot
    }

    static var hasGrokBotCredentials: Bool {
        FileManager.default.fileExists(atPath: grokBotSecretsURL.path)
    }

    static func fetchGrokBot(allowKeychainPrompt: Bool = false) async throws -> AgentUsageSnapshot {
        let session = try loadGrokBotSession(allowKeychainPrompt: allowKeychainPrompt)
        let cached = cachedGrokBotSession(fingerprint: session.fingerprint)
        let accessToken = cached?.accessToken ?? session.accessToken
        let refreshToken = cached?.refreshToken ?? session.refreshToken
        let json: [String: Any]
        do {
            json = try await postGrokBotUsage(token: accessToken)
        } catch FetchError.signedOut {
            let refreshed = try await refreshGrokBot(refreshToken: refreshToken)
            storeGrokBotSession(fingerprint: session.fingerprint, accessToken: refreshed.accessToken, refreshToken: refreshed.refreshToken)
            do {
                json = try await postGrokBotUsage(token: refreshed.accessToken)
            } catch FetchError.signedOut {
                throw FetchError.loginExpired
            }
        }
        var snapshot = AgentUsageParser.parseGrokBot(json)
        snapshot.status = snapshot.hasMeters ? .ready : .unavailable
        let left = snapshot.sevenDay.map { Int($0.remainingPercent.rounded()) } ?? -1
        NotchFlowLog.agents.info("Grok Bot usage 7dLeft=\(left, privacy: .public)")
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

    // MARK: - Cursor credentials

    private enum CursorLogin {
        case ready(String)
        case expired
        case missing
    }

    private static func postCursor(_ method: String, token: String) async throws -> [String: Any] {
        guard let url = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/\(method)") else {
            throw FetchError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return try await perform(request, provider: "Cursor")
    }

    private static let cursorSafeStoragePrefix = "cursor-safe-storage:v1:"
    private static var didPromptForCursorKeychain = false
    private static var cachedCursorSafeStorageKey: Data?

    /// Reads the Cursor login already on this Mac. A rotated access token is kept in
    /// NotchFlow's cache. Cursor's database and `auth.json` are never written.
    private static func cursorLogin(now: Date = Date()) -> CursorLogin {
        let stored = cursorStoredLogin()
        let cached = cachedCursorAccessToken(refreshToken: stored.refreshToken)
        let candidates = [cached, stored.accessToken].compactMap { $0 }
        guard !candidates.isEmpty || stored.refreshToken != nil else { return .missing }
        if let token = preferredCursorAccessToken(candidates, now: now) {
            return .ready(token)
        }
        return .expired
    }

    /// Picks the usable bearer. An expired access token is refreshed from Cursor's
    /// refresh token when one is already on this Mac.
    private static func cursorAccessToken(now: Date = Date(), allowKeychainPrompt: Bool = false) async throws -> String {
        let stored = try unlockedCursorLogin(allowKeychainPrompt: allowKeychainPrompt)
        let cached = cachedCursorAccessToken(refreshToken: stored.refreshToken)
        let candidates = [cached, stored.accessToken].compactMap { $0 }
        if let token = preferredCursorAccessToken(candidates, now: now) {
            return token
        }
        if stored.refreshToken != nil {
            if let refreshed = try await refreshedCursorAccessToken(stored: stored, allowKeychainPrompt: allowKeychainPrompt) {
                return refreshed
            }
        }
        if candidates.isEmpty {
            throw FetchError.signedOut
        }
        throw FetchError.loginExpired
    }

    private static func refreshedCursorAccessToken(
        stored explicit: CursorStoredLogin? = nil,
        allowKeychainPrompt: Bool = false
    ) async throws -> String? {
        let stored: CursorStoredLogin
        if let explicit {
            stored = explicit
        } else {
            stored = try unlockedCursorLogin(allowKeychainPrompt: allowKeychainPrompt)
        }
        let cached = cachedCursorSession(refreshToken: stored.refreshToken)
        let refreshToken = cached?.refreshToken ?? stored.refreshToken
        guard let refreshToken, !refreshToken.isEmpty else { return nil }
        let refreshed = try await refreshCursor(refreshToken: refreshToken)
        let fingerprint = secretFingerprint(stored.refreshToken ?? refreshToken)
        storeCursorSession(
            fingerprint: fingerprint,
            accessToken: refreshed.accessToken,
            refreshToken: refreshed.refreshToken
        )
        return refreshed.accessToken
    }

    /// Cursor stores `cursorAuth/*` as Electron safeStorage ciphertext. The blob is not a bearer token.
    static func unwrapCursorSafeStorageToken(_ stored: String, password: String) -> String? {
        guard let key = ClaudeDesktopCredentials.deriveKey(password: password) else { return nil }
        return unwrapCursorToken(stored, key: key)
    }

    private static func unlockedCursorLogin(allowKeychainPrompt: Bool) throws -> CursorStoredLogin {
        let raw = cursorStoredLogin()
        let sealed = [raw.accessToken, raw.refreshToken].compactMap { $0 }.contains { $0.hasPrefix(cursorSafeStoragePrefix) }
        guard sealed else { return raw }
        guard let key = try cursorSafeStorageKey(allowPrompt: allowKeychainPrompt) else {
            NotchFlowLog.agents.info("Cursor safe storage key is missing")
            throw FetchError.needsKeychainAccess
        }
        let access = raw.accessToken.flatMap { unwrapCursorToken($0, key: key) }
        let refresh = raw.refreshToken.flatMap { unwrapCursorToken($0, key: key) }
        guard access != nil || refresh != nil else {
            NotchFlowLog.agents.info("Cursor safe storage token did not decrypt")
            throw FetchError.loginExpired
        }
        let accessShape = access.map(cursorTokenShape) ?? "missing"
        let refreshShape = refresh.map(cursorTokenShape) ?? "missing"
        let same = access != nil && access == refresh
        NotchFlowLog.agents.info("Cursor login unlocked access=\(accessShape, privacy: .public) refresh=\(refreshShape, privacy: .public) same=\(same, privacy: .public)")
        return CursorStoredLogin(accessToken: access, refreshToken: refresh)
    }

    private static func cursorTokenShape(_ token: String) -> String {
        let body = token.split(separator: "::", maxSplits: 1).last.map(String.init) ?? token
        return body.split(separator: ".").count >= 3 ? "jwt" : "opaque"
    }

    private static func unwrapCursorToken(_ stored: String, key: Data) -> String? {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(cursorSafeStoragePrefix) else {
            return cursorTokenString(trimmed)
        }
        let encoded = String(trimmed.dropFirst(cursorSafeStoragePrefix.count))
        guard var encrypted = Data(base64Encoded: encoded) else { return nil }
        if encrypted.prefix(3) == Data("v11".utf8) {
            encrypted.replaceSubrange(0..<3, with: Data("v10".utf8))
        }
        guard let plain = ClaudeDesktopCredentials.decrypt(encrypted, key: key) else {
            return nil
        }
        return cursorTokenString(String(data: plain, encoding: .utf8))
    }

    private static func cursorSafeStorageKey(allowPrompt: Bool) throws -> Data? {
        if let cachedCursorSafeStorageKey { return cachedCursorSafeStorageKey }
        let accounts = ["Cursor", "Cursor Key"]
        var locked = false
        for account in accounts {
            let password: String?
            do {
                password = try copyGenericPassword(
                    service: "Cursor Safe Storage",
                    account: account,
                    allowPrompt: allowPrompt,
                    provider: "Cursor"
                )
            } catch FetchError.needsKeychainAccess {
                locked = true
                continue
            }
            guard let password, let key = ClaudeDesktopCredentials.deriveKey(password: password) else { continue }
            guard cursorSafeStorageKeyOpensStoredTokens(key) else { continue }
            cachedCursorSafeStorageKey = key
            return key
        }
        if locked { throw FetchError.needsKeychainAccess }
        return nil
    }

    private static func cursorSafeStorageKeyOpensStoredTokens(_ key: Data) -> Bool {
        let raw = cursorStoredLogin()
        return [raw.accessToken, raw.refreshToken].compactMap { $0 }.contains { token in
            token.hasPrefix(cursorSafeStoragePrefix) && unwrapCursorToken(token, key: key) != nil
        }
    }

    static func cursorTokenIsExpired(_ token: String, now: Date) -> Bool {
        guard let expiresAt = cursorTokenExpiry(token) else { return false }
        return expiresAt.timeIntervalSince(now) <= 2 * 60
    }

    private static func cursorTokenExpiry(_ token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder != 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: String(payload)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return AgentUsageParser.parseResetDate(json["exp"])
    }

    static func preferredCursorAccessToken(_ tokens: [String], now: Date) -> String? {
        tokens
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !cursorTokenIsExpired($0, now: now) }
            .max { lhs, rhs in
                (cursorTokenExpiry(lhs) ?? .distantFuture) < (cursorTokenExpiry(rhs) ?? .distantFuture)
            }
    }

    private struct CursorStoredLogin {
        var accessToken: String?
        var refreshToken: String?
    }

    private static func cursorStoredLogin() -> CursorStoredLogin {
        let database = cursorDatabaseLogin()
        let file = cursorFileLogin()
        return CursorStoredLogin(
            accessToken: newerCursorToken(database.accessToken, file.accessToken),
            refreshToken: database.refreshToken ?? file.refreshToken
        )
    }

    private static func newerCursorToken(_ lhs: String?, _ rhs: String?) -> String? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            let left = cursorTokenExpiry(lhs) ?? .distantPast
            let right = cursorTokenExpiry(rhs) ?? .distantPast
            return left >= right ? lhs : rhs
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        default:
            return nil
        }
    }

    private static func cursorFileLogin() -> CursorStoredLogin {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor/auth.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return CursorStoredLogin(accessToken: nil, refreshToken: nil)
        }
        return CursorStoredLogin(
            accessToken: cursorTokenString(root["accessToken"] ?? root["access_token"]),
            refreshToken: cursorTokenString(root["refreshToken"] ?? root["refresh_token"])
        )
    }

    private static func cursorDatabaseLogin() -> CursorStoredLogin {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
        guard FileManager.default.fileExists(atPath: url.path) else {
            return CursorStoredLogin(accessToken: nil, refreshToken: nil)
        }
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            return CursorStoredLogin(accessToken: nil, refreshToken: nil)
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 2000)
        return CursorStoredLogin(
            accessToken: cursorDatabaseValue(db, key: "cursorAuth/accessToken"),
            refreshToken: cursorDatabaseValue(db, key: "cursorAuth/refreshToken")
        )
    }

    private static func cursorDatabaseValue(_ db: OpaquePointer, key: String) -> String? {
        let sql = "SELECT value FROM ItemTable WHERE key = ? LIMIT 1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(statement) == SQLITE_ROW, let cString = sqlite3_column_text(statement, 0) else {
            return nil
        }
        return cursorTokenString(String(cString: cString))
    }

    private static func cursorTokenString(_ any: Any?) -> String? {
        guard var token = any as? String else { return nil }
        token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.hasPrefix("\""), token.hasSuffix("\""), token.count >= 2 {
            token = String(token.dropFirst().dropLast())
        }
        return token.isEmpty ? nil : token
    }

    private static var cursorOAuthCacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchFlow/Agents/cursor-oauth.json")
    }

    private struct CachedCursorSession {
        var accessToken: String
        var refreshToken: String
    }

    private static func cachedCursorAccessToken(refreshToken: String?) -> String? {
        guard let session = cachedCursorSession(refreshToken: refreshToken),
              !cursorTokenIsExpired(session.accessToken, now: Date()) else {
            return nil
        }
        return session.accessToken
    }

    private static func cachedCursorSession(refreshToken: String?) -> CachedCursorSession? {
        guard let refreshToken, !refreshToken.isEmpty else { return nil }
        let fingerprint = secretFingerprint(refreshToken)
        guard let data = try? Data(contentsOf: cursorOAuthCacheURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["fingerprint"] as? String == fingerprint,
              let access = root["accessToken"] as? String,
              !access.isEmpty else {
            return nil
        }
        let cachedRefresh = (root["refreshToken"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? refreshToken
        return CachedCursorSession(accessToken: access, refreshToken: cachedRefresh)
    }

    private static func storeCursorSession(fingerprint: String, accessToken: String, refreshToken: String) {
        let payload: [String: String] = [
            "fingerprint": fingerprint,
            "accessToken": accessToken,
            "refreshToken": refreshToken,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        try? SecureFileWriter.write(data, to: cursorOAuthCacheURL)
    }

    private struct RefreshedCursorToken {
        var accessToken: String
        var refreshToken: String
    }

    private static func refreshCursor(refreshToken: String) async throws -> RefreshedCursorToken {
        guard let url = URL(string: "https://api2.cursor.sh/oauth/token") else {
            throw FetchError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let body: [String: String] = [
            "client_id": "KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB",
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let json: [String: Any]
        do {
            json = try await perform(request, provider: "Cursor")
        } catch FetchError.signedOut {
            throw FetchError.loginExpired
        }
        let shouldLogout = (json["shouldLogout"] as? Bool) == true
        guard !shouldLogout,
              let access = json["access_token"] as? String,
              !access.isEmpty else {
            throw FetchError.loginExpired
        }
        let rotated = (json["refresh_token"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? refreshToken
        return RefreshedCursorToken(accessToken: access, refreshToken: rotated)
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

    // MARK: - Grok Build credentials

    private enum GrokBuildLogin {
        case ready(String)
        case expired
        case missing
    }

    /// Picks the `grok login` bearer (`key`) from `~/.grok/auth.json`.
    /// OIDC entries beat bare keys. An expired-only file does not get sent.
    static func selectGrokBuildToken(_ root: [String: Any], now: Date = Date()) -> String? {
        switch classifyGrokBuild(root, now: now) {
        case .ready(let token): token
        case .expired, .missing: nil
        }
    }

    static func grokBuildLoginState(_ root: [String: Any], now: Date = Date()) -> String {
        switch classifyGrokBuild(root, now: now) {
        case .ready: "ready"
        case .expired: "expired"
        case .missing: "missing"
        }
    }

    private static func grokBuildLogin(now: Date = Date()) -> GrokBuildLogin {
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
        return classifyGrokBuild(root, now: now)
    }

    private struct GrokBuildCandidate {
        var token: String
        var hasRefresh: Bool
        var expiresAt: Date?
        var prefersOIDC: Bool
    }

    private static func classifyGrokBuild(_ root: [String: Any], now: Date) -> GrokBuildLogin {
        let candidates = grokBuildCandidates(root)
        guard !candidates.isEmpty else { return .missing }
        let usable = candidates.filter { candidate in
            guard let expiresAt = candidate.expiresAt else { return true }
            return expiresAt.timeIntervalSince(now) > 2 * 60
        }
        guard let best = usable.max(by: grokBuildIsWorse) else { return .expired }
        return .ready(best.token)
    }

    private static func grokBuildIsWorse(_ lhs: GrokBuildCandidate, _ rhs: GrokBuildCandidate) -> Bool {
        if lhs.hasRefresh != rhs.hasRefresh { return !lhs.hasRefresh }
        if lhs.prefersOIDC != rhs.prefersOIDC { return !lhs.prefersOIDC }
        let left = lhs.expiresAt ?? .distantPast
        let right = rhs.expiresAt ?? .distantPast
        return left < right
    }

    private static func grokBuildCandidates(_ root: [String: Any]) -> [GrokBuildCandidate] {
        if let direct = grokBuildCandidate(root, label: "") {
            return [direct]
        }
        return root.compactMap { label, value in
            guard let object = value as? [String: Any] else { return nil }
            return grokBuildCandidate(object, label: label)
        }
    }

    private static func grokBuildCandidate(_ object: [String: Any], label: String) -> GrokBuildCandidate? {
        guard let token = (object["key"] as? String) ?? (object["access_token"] as? String) else { return nil }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("xai-") else { return nil }
        let refresh = (object["refresh_token"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return GrokBuildCandidate(
            token: trimmed,
            hasRefresh: !refresh.isEmpty,
            expiresAt: AgentUsageParser.parseResetDate(object["expires_at"] ?? object["expiresAt"]),
            prefersOIDC: label.contains("auth.x.ai") || label.contains("accounts.x.ai")
        )
    }

    // MARK: - Grok Bot credentials

    private struct GrokBotSession {
        var accessToken: String
        var refreshToken: String
        var fingerprint: String
    }

    private static var grokBotSecretsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Grok Bot/sand-secrets.json")
    }

    private static var grokBotOAuthCacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchFlow/Agents/grokbot-oauth.json")
    }

    private static func loadGrokBotSession(allowKeychainPrompt: Bool) throws -> GrokBotSession {
        guard let data = try? Data(contentsOf: grokBotSecretsURL) else {
            throw FetchError.signedOut
        }
        let password: String
        do {
            guard let found = try grokBotSafeStoragePassword(allowPrompt: allowKeychainPrompt) else {
                throw FetchError.signedOut
            }
            password = found
        } catch FetchError.needsKeychainAccess {
            throw FetchError.needsKeychainAccess
        }
        guard let key = ClaudeDesktopCredentials.deriveKey(password: password),
              let session = decodeGrokBotSession(data, key: key) else {
            throw FetchError.invalidResponse
        }
        return session
    }

    static func decodeGrokBotSecretsForTest(_ data: Data, password: String) -> (accessToken: String, refreshToken: String)? {
        guard let key = ClaudeDesktopCredentials.deriveKey(password: password),
              let session = decodeGrokBotSession(data, key: key) else {
            return nil
        }
        return (session.accessToken, session.refreshToken)
    }

    private static func decodeGrokBotSession(_ data: Data, key: Data) -> GrokBotSession? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accounts = grokBotAccountsObject(root["cursor-accounts"]),
              let active = accounts["active"] as? String,
              let map = accounts["accounts"] as? [String: Any],
              let entry = map[active] as? [String: Any],
              let access = decryptGrokBotField(entry["cursor-access-token"], key: key),
              let refresh = decryptGrokBotField(entry["cursor-refresh-token"], key: key),
              !access.isEmpty, !refresh.isEmpty else {
            return nil
        }
        return GrokBotSession(accessToken: access, refreshToken: refresh, fingerprint: secretFingerprint(refresh))
    }

    private static func grokBotAccountsObject(_ value: Any?) -> [String: Any]? {
        if let object = value as? [String: Any] { return object }
        guard let text = value as? String,
              let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private static func decryptGrokBotField(_ value: Any?, key: Data) -> String? {
        guard let encoded = value as? String else { return nil }
        let trimmed = encoded.trimmingCharacters(in: .whitespacesAndNewlines)
        var encrypted = Data(base64Encoded: trimmed) ?? Data(trimmed.utf8)
        if encrypted.prefix(3) == Data("v11".utf8) {
            encrypted.replaceSubrange(0..<3, with: Data("v10".utf8))
        }
        guard let plain = ClaudeDesktopCredentials.decrypt(encrypted, key: key),
              let text = String(data: plain, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }
        return text
    }

    private static func grokBotSafeStoragePassword(allowPrompt: Bool) throws -> String? {
        try copyGenericPassword(
            service: "Grok Bot Safe Storage",
            account: "Grok Bot Key",
            allowPrompt: allowPrompt
        )
    }

    private static func copyGenericPassword(
        service: String,
        account: String,
        allowPrompt: Bool,
        provider: String = "Grok Bot"
    ) throws -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if !allowPrompt {
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = context
        }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let password = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !password.isEmpty else {
                return nil
            }
            return password
        case errSecItemNotFound:
            return nil
        case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled:
            throw FetchError.needsKeychainAccess
        default:
            NotchFlowLog.agents.info("\(provider, privacy: .public) keychain status \(status, privacy: .public)")
            return nil
        }
    }

    private static func secretFingerprint(_ refreshToken: String) -> String {
        let digest = SHA256.hash(data: Data(refreshToken.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private struct CachedGrokBotSession {
        var accessToken: String
        var refreshToken: String
    }

    /// NotchFlow's own rotated pair. The fingerprint is the refresh token still in Grok Bot's file.
    private static func cachedGrokBotSession(fingerprint: String) -> CachedGrokBotSession? {
        guard let data = try? Data(contentsOf: grokBotOAuthCacheURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["fingerprint"] as? String == fingerprint,
              let token = root["accessToken"] as? String,
              !token.isEmpty else {
            return nil
        }
        let refresh = (root["refreshToken"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? ""
        guard !refresh.isEmpty else { return nil }
        return CachedGrokBotSession(accessToken: token, refreshToken: refresh)
    }

    private static func storeGrokBotSession(fingerprint: String, accessToken: String, refreshToken: String) {
        let payload: [String: String] = [
            "fingerprint": fingerprint,
            "accessToken": accessToken,
            "refreshToken": refreshToken,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        try? SecureFileWriter.write(data, to: grokBotOAuthCacheURL)
    }

    private static func postGrokBotUsage(token: String) async throws -> [String: Any] {
        guard let url = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetSandUsageStatus") else {
            throw FetchError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue("sand", forHTTPHeaderField: "x-cursor-client-type")
        request.setValue("0.1.0", forHTTPHeaderField: "x-cursor-client-version")
        request.setValue("prod", forHTTPHeaderField: "x-sand-box-namespace")
        request.setValue("true", forHTTPHeaderField: "x-ghost-mode")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return try await perform(request, provider: "Grok Bot")
    }

    private struct RefreshedGrokBotToken {
        var accessToken: String
        var refreshToken: String
    }

    private static func refreshGrokBot(refreshToken: String) async throws -> RefreshedGrokBotToken {
        guard let url = URL(string: "https://api2.cursor.sh/oauth/token") else {
            throw FetchError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let body: [String: String] = [
            "client_id": "KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB",
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let json: [String: Any]
        do {
            json = try await perform(request, provider: "Grok Bot")
        } catch FetchError.signedOut {
            throw FetchError.loginExpired
        }
        guard let access = json["access_token"] as? String, !access.isEmpty else {
            throw FetchError.invalidResponse
        }
        let rotated = (json["refresh_token"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? refreshToken
        return RefreshedGrokBotToken(accessToken: access, refreshToken: rotated)
    }
}
