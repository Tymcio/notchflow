import Foundation
import SQLite3

/// Cursor desktop login from its `state.vscdb` (Electron safeStorage) or `~/.cursor/auth.json`.
enum CursorUsageProvider: AgentUsageProvider {
    typealias FetchError = AgentUsageClient.FetchError

    static let agent: AgentKind = .cursor

    static var hasCredentials: Bool {
        switch login() {
        case .missing: false
        case .ready, .expired: true
        }
    }

    static func fetch(allowKeychainPrompt: Bool) async throws -> AgentUsageSnapshot {
        do {
            return try await loadUsage(allowKeychainPrompt: false)
        } catch FetchError.needsKeychainAccess {
            let shouldPrompt = allowKeychainPrompt || !didPromptForKeychain
            guard shouldPrompt else { throw FetchError.needsKeychainAccess }
            didPromptForKeychain = true
            return try await loadUsage(allowKeychainPrompt: true)
        }
    }

    private static func loadUsage(allowKeychainPrompt: Bool) async throws -> AgentUsageSnapshot {
        var token = try await accessToken(allowKeychainPrompt: allowKeychainPrompt)
        let usage: [String: Any]
        do {
            usage = try await post("GetCurrentPeriodUsage", token: token)
        } catch FetchError.signedOut {
            guard let refreshed = try await refreshedAccessToken(allowKeychainPrompt: allowKeychainPrompt) else {
                throw FetchError.loginExpired
            }
            token = refreshed
            do {
                usage = try await post("GetCurrentPeriodUsage", token: token)
            } catch FetchError.signedOut {
                throw FetchError.loginExpired
            }
        }
        let plan = try? await post("GetPlanInfo", token: token)
        var snapshot = AgentUsageParser.parseCursor(usage: usage, plan: plan)
        snapshot.status = snapshot.hasMeters ? .ready : .unavailable
        let summary = snapshot.meters
            .map { "\($0.label)=\(Int($0.window.remainingPercent.rounded()))" }
            .joined(separator: " ")
        NotchFlowLog.agents.info("Cursor usage \(summary, privacy: .public)")
        return snapshot
    }

    // MARK: - Credentials

    private enum Login {
        case ready(String)
        case expired
        case missing
    }

    private static func post(_ method: String, token: String) async throws -> [String: Any] {
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
        request.setValue(AgentUsageHTTP.userAgent, forHTTPHeaderField: "User-Agent")
        return try await AgentUsageHTTP.perform(request, provider: "Cursor")
    }

    private static let safeStoragePrefix = "cursor-safe-storage:v1:"
    private static var didPromptForKeychain = false
    private static var cachedSafeStorageKey: Data?

    /// Reads the Cursor login already on this Mac. A rotated access token is kept in
    /// NotchFlow's cache. Cursor's database and `auth.json` are never written.
    private static func login(now: Date = Date()) -> Login {
        let stored = storedLogin()
        let cached = cachedAccessToken(refreshToken: stored.refreshToken)
        let candidates = [cached, stored.accessToken].compactMap { $0 }
        guard !candidates.isEmpty || stored.refreshToken != nil else { return .missing }
        if let token = preferredAccessToken(candidates, now: now) {
            return .ready(token)
        }
        return .expired
    }

    /// Picks the usable bearer. An expired access token is refreshed from Cursor's
    /// refresh token when one is already on this Mac.
    private static func accessToken(now: Date = Date(), allowKeychainPrompt: Bool = false) async throws -> String {
        let stored = try unlockedLogin(allowKeychainPrompt: allowKeychainPrompt)
        let cached = cachedAccessToken(refreshToken: stored.refreshToken)
        let candidates = [cached, stored.accessToken].compactMap { $0 }
        if let token = preferredAccessToken(candidates, now: now) {
            return token
        }
        if stored.refreshToken != nil {
            if let refreshed = try await refreshedAccessToken(stored: stored, allowKeychainPrompt: allowKeychainPrompt) {
                return refreshed
            }
        }
        if candidates.isEmpty {
            throw FetchError.signedOut
        }
        throw FetchError.loginExpired
    }

    private static func refreshedAccessToken(
        stored explicit: StoredLogin? = nil,
        allowKeychainPrompt: Bool = false
    ) async throws -> String? {
        let stored: StoredLogin
        if let explicit {
            stored = explicit
        } else {
            stored = try unlockedLogin(allowKeychainPrompt: allowKeychainPrompt)
        }
        let cached = cachedSession(refreshToken: stored.refreshToken)
        let refreshToken = cached?.refreshToken ?? stored.refreshToken
        guard let refreshToken, !refreshToken.isEmpty else { return nil }
        let refreshed = try await refresh(refreshToken: refreshToken)
        let fingerprint = AgentUsageKeychain.secretFingerprint(stored.refreshToken ?? refreshToken)
        storeSession(
            fingerprint: fingerprint,
            accessToken: refreshed.accessToken,
            refreshToken: refreshed.refreshToken
        )
        return refreshed.accessToken
    }

    /// Cursor stores `cursorAuth/*` as Electron safeStorage ciphertext. The blob is not a bearer token.
    static func unwrapSafeStorageToken(_ stored: String, password: String) -> String? {
        guard let key = ClaudeDesktopCredentials.deriveKey(password: password) else { return nil }
        return unwrapToken(stored, key: key)
    }

    private static func unlockedLogin(allowKeychainPrompt: Bool) throws -> StoredLogin {
        let raw = storedLogin()
        let sealed = [raw.accessToken, raw.refreshToken].compactMap { $0 }.contains { $0.hasPrefix(safeStoragePrefix) }
        guard sealed else { return raw }
        guard let key = try safeStorageKey(allowPrompt: allowKeychainPrompt) else {
            NotchFlowLog.agents.info("Cursor safe storage key is missing")
            throw FetchError.needsKeychainAccess
        }
        let access = raw.accessToken.flatMap { unwrapToken($0, key: key) }
        let refresh = raw.refreshToken.flatMap { unwrapToken($0, key: key) }
        guard access != nil || refresh != nil else {
            NotchFlowLog.agents.info("Cursor safe storage token did not decrypt")
            throw FetchError.loginExpired
        }
        let accessShape = access.map(tokenShape) ?? "missing"
        let refreshShape = refresh.map(tokenShape) ?? "missing"
        let same = access != nil && access == refresh
        NotchFlowLog.agents.info("Cursor login unlocked access=\(accessShape, privacy: .public) refresh=\(refreshShape, privacy: .public) same=\(same, privacy: .public)")
        return StoredLogin(accessToken: access, refreshToken: refresh)
    }

    private static func tokenShape(_ token: String) -> String {
        let body = token.split(separator: "::", maxSplits: 1).last.map(String.init) ?? token
        return body.split(separator: ".").count >= 3 ? "jwt" : "opaque"
    }

    private static func unwrapToken(_ stored: String, key: Data) -> String? {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(safeStoragePrefix) else {
            return tokenString(trimmed)
        }
        let encoded = String(trimmed.dropFirst(safeStoragePrefix.count))
        guard var encrypted = Data(base64Encoded: encoded) else { return nil }
        if encrypted.prefix(3) == Data("v11".utf8) {
            encrypted.replaceSubrange(0..<3, with: Data("v10".utf8))
        }
        guard let plain = ClaudeDesktopCredentials.decrypt(encrypted, key: key) else {
            return nil
        }
        return tokenString(String(data: plain, encoding: .utf8))
    }

    private static func safeStorageKey(allowPrompt: Bool) throws -> Data? {
        if let cachedSafeStorageKey { return cachedSafeStorageKey }
        let accounts = ["Cursor", "Cursor Key"]
        var locked = false
        for account in accounts {
            let password: String?
            do {
                password = try AgentUsageKeychain.copyGenericPassword(
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
            guard safeStorageKeyOpensStoredTokens(key) else { continue }
            cachedSafeStorageKey = key
            return key
        }
        if locked { throw FetchError.needsKeychainAccess }
        return nil
    }

    private static func safeStorageKeyOpensStoredTokens(_ key: Data) -> Bool {
        let raw = storedLogin()
        return [raw.accessToken, raw.refreshToken].compactMap { $0 }.contains { token in
            token.hasPrefix(safeStoragePrefix) && unwrapToken(token, key: key) != nil
        }
    }

    static func tokenIsExpired(_ token: String, now: Date) -> Bool {
        guard let expiresAt = tokenExpiry(token) else { return false }
        return expiresAt.timeIntervalSince(now) <= 2 * 60
    }

    private static func tokenExpiry(_ token: String) -> Date? {
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

    static func preferredAccessToken(_ tokens: [String], now: Date) -> String? {
        tokens
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !tokenIsExpired($0, now: now) }
            .max { lhs, rhs in
                (tokenExpiry(lhs) ?? .distantFuture) < (tokenExpiry(rhs) ?? .distantFuture)
            }
    }

    private struct StoredLogin {
        var accessToken: String?
        var refreshToken: String?
    }

    private static func storedLogin() -> StoredLogin {
        let database = databaseLogin()
        let file = fileLogin()
        return StoredLogin(
            accessToken: newerToken(database.accessToken, file.accessToken),
            refreshToken: database.refreshToken ?? file.refreshToken
        )
    }

    private static func newerToken(_ lhs: String?, _ rhs: String?) -> String? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            let left = tokenExpiry(lhs) ?? .distantPast
            let right = tokenExpiry(rhs) ?? .distantPast
            return left >= right ? lhs : rhs
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        default:
            return nil
        }
    }

    private static func fileLogin() -> StoredLogin {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor/auth.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return StoredLogin(accessToken: nil, refreshToken: nil)
        }
        return StoredLogin(
            accessToken: tokenString(root["accessToken"] ?? root["access_token"]),
            refreshToken: tokenString(root["refreshToken"] ?? root["refresh_token"])
        )
    }

    private static func databaseLogin() -> StoredLogin {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
        guard FileManager.default.fileExists(atPath: url.path) else {
            return StoredLogin(accessToken: nil, refreshToken: nil)
        }
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            return StoredLogin(accessToken: nil, refreshToken: nil)
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 2000)
        return StoredLogin(
            accessToken: databaseValue(db, key: "cursorAuth/accessToken"),
            refreshToken: databaseValue(db, key: "cursorAuth/refreshToken")
        )
    }

    private static func databaseValue(_ db: OpaquePointer, key: String) -> String? {
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
        return tokenString(String(cString: cString))
    }

    private static func tokenString(_ any: Any?) -> String? {
        guard var token = any as? String else { return nil }
        token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.hasPrefix("\""), token.hasSuffix("\""), token.count >= 2 {
            token = String(token.dropFirst().dropLast())
        }
        return token.isEmpty ? nil : token
    }

    private static var oauthCacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchFlow/Agents/cursor-oauth.json")
    }

    private struct CachedSession {
        var accessToken: String
        var refreshToken: String
    }

    private static func cachedAccessToken(refreshToken: String?) -> String? {
        guard let session = cachedSession(refreshToken: refreshToken),
              !tokenIsExpired(session.accessToken, now: Date()) else {
            return nil
        }
        return session.accessToken
    }

    private static func cachedSession(refreshToken: String?) -> CachedSession? {
        guard let refreshToken, !refreshToken.isEmpty else { return nil }
        let fingerprint = AgentUsageKeychain.secretFingerprint(refreshToken)
        guard let data = try? Data(contentsOf: oauthCacheURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["fingerprint"] as? String == fingerprint,
              let access = root["accessToken"] as? String,
              !access.isEmpty else {
            return nil
        }
        let cachedRefresh = (root["refreshToken"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? refreshToken
        return CachedSession(accessToken: access, refreshToken: cachedRefresh)
    }

    private static func storeSession(fingerprint: String, accessToken: String, refreshToken: String) {
        let payload: [String: String] = [
            "fingerprint": fingerprint,
            "accessToken": accessToken,
            "refreshToken": refreshToken,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        try? SecureFileWriter.write(data, to: oauthCacheURL)
    }

    private struct RefreshedToken {
        var accessToken: String
        var refreshToken: String
    }

    private static func refresh(refreshToken: String) async throws -> RefreshedToken {
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
            json = try await AgentUsageHTTP.perform(request, provider: "Cursor")
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
        return RefreshedToken(accessToken: access, refreshToken: rotated)
    }
}
