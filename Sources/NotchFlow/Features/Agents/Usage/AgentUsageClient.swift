import CryptoKit
import Foundation
import os
import Security

/// One provider's usage meter: finds the login already on this Mac and asks the provider
/// for its limits. Tokens stay in memory.
protocol AgentUsageProvider {
    static var agent: AgentKind { get }
    static var hasCredentials: Bool { get }
    static func fetch(allowKeychainPrompt: Bool) async throws -> AgentUsageSnapshot
}

/// Reads the Claude Code / Codex / Cursor / Grok logins already on this Mac and asks the
/// provider for 5-hour / 7-day usage. Each provider lives in its own file.
enum AgentUsageClient {
    enum FetchError: Error {
        case signedOut
        case needsKeychainAccess
        case loginExpired
        case rateLimited(retryAfter: TimeInterval?)
        case http(Int)
        case invalidResponse
    }

    // MARK: - Claude

    static var hasClaudeCredentials: Bool { ClaudeUsageProvider.hasCredentials }

    static func claudePlanName(subscriptionType: String?, rateLimitTier: String?) -> String? {
        ClaudeUsageProvider.formatPlan(subscriptionType: subscriptionType, rateLimitTier: rateLimitTier)
    }

    static func fetchClaude(allowKeychainPrompt: Bool = false) async throws -> AgentUsageSnapshot {
        try await ClaudeUsageProvider.fetch(allowKeychainPrompt: allowKeychainPrompt)
    }

    static func parseClaudeCredentialFile(_ data: Data) -> (accessToken: String, planName: String?)? {
        ClaudeUsageProvider.parseCredentialFile(data)
    }

    // MARK: - Codex

    static var hasCodexCredentials: Bool { CodexUsageProvider.hasCredentials }

    static func fetchCodex() async throws -> AgentUsageSnapshot {
        try await CodexUsageProvider.fetch(allowKeychainPrompt: false)
    }

    static func parseCodexAuthFile(_ data: Data) -> (accessToken: String, accountID: String?)? {
        CodexUsageProvider.parseAuthFile(data)
    }

    // MARK: - Cursor

    static var hasCursorCredentials: Bool { CursorUsageProvider.hasCredentials }

    static func fetchCursor(allowKeychainPrompt: Bool = false) async throws -> AgentUsageSnapshot {
        try await CursorUsageProvider.fetch(allowKeychainPrompt: allowKeychainPrompt)
    }

    static func unwrapCursorSafeStorageToken(_ stored: String, password: String) -> String? {
        CursorUsageProvider.unwrapSafeStorageToken(stored, password: password)
    }

    static func cursorTokenIsExpired(_ token: String, now: Date) -> Bool {
        CursorUsageProvider.tokenIsExpired(token, now: now)
    }

    static func preferredCursorAccessToken(_ tokens: [String], now: Date) -> String? {
        CursorUsageProvider.preferredAccessToken(tokens, now: now)
    }

    // MARK: - Grok Build

    static var hasGrokBuildCredentials: Bool { GrokBuildUsageProvider.hasCredentials }

    static func fetchGrokBuild() async throws -> AgentUsageSnapshot {
        try await GrokBuildUsageProvider.fetch(allowKeychainPrompt: false)
    }

    static func selectGrokBuildToken(_ root: [String: Any], now: Date = Date()) -> String? {
        GrokBuildUsageProvider.selectToken(root, now: now)
    }

    static func grokBuildLoginState(_ root: [String: Any], now: Date = Date()) -> String {
        GrokBuildUsageProvider.loginState(root, now: now)
    }

    // MARK: - Grok Bot

    static var hasGrokBotCredentials: Bool { GrokBotUsageProvider.hasCredentials }

    static func fetchGrokBot(allowKeychainPrompt: Bool = false) async throws -> AgentUsageSnapshot {
        try await GrokBotUsageProvider.fetch(allowKeychainPrompt: allowKeychainPrompt)
    }

    static func decodeGrokBotSecretsForTest(_ data: Data, password: String) -> (accessToken: String, refreshToken: String)? {
        GrokBotUsageProvider.decodeSecrets(data, password: password)
    }

    // MARK: - Legacy files

    /// Earlier builds wrote refreshed Cursor and Grok Bot tokens to these files in plain text.
    static let legacyTokenCacheNames = ["cursor-oauth.json", "grokbot-oauth.json"]

    static var legacyTokenCacheDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchFlow/Agents", isDirectory: true)
    }

    /// Deletes token caches older builds left on disk. Returns the files it removed.
    @discardableResult
    static func removeLegacyTokenCaches(in directory: URL = legacyTokenCacheDirectory) -> [URL] {
        var removed: [URL] = []
        for name in legacyTokenCacheNames {
            let url = directory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                try FileManager.default.removeItem(at: url)
                removed.append(url)
            } catch {
                NotchFlowLog.agents.error("Could not remove legacy token cache \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        if !removed.isEmpty {
            NotchFlowLog.agents.info("Removed \(removed.count, privacy: .public) legacy token cache file(s)")
        }
        return removed
    }
}

/// A token pair NotchFlow refreshed itself for another app's login. Kept in memory for the
/// life of the process only; another app's decrypted tokens are never written to disk.
struct RotatedTokenSession: Equatable, Sendable {
    /// Fingerprint of the refresh token still stored by the other app.
    var fingerprint: String
    var accessToken: String
    var refreshToken: String
}

final class RotatedTokenCache: Sendable {
    private let state = OSAllocatedUnfairLock<RotatedTokenSession?>(initialState: nil)

    func session(matching fingerprint: String) -> RotatedTokenSession? {
        state.withLock { session in
            guard let session, session.fingerprint == fingerprint else { return nil }
            return session
        }
    }

    func store(_ session: RotatedTokenSession) {
        state.withLock { $0 = session }
    }

    func clear() {
        state.withLock { $0 = nil }
    }
}

// MARK: - Shared helpers

enum AgentUsageHTTP {
    typealias FetchError = AgentUsageClient.FetchError

    static func perform(_ request: URLRequest, provider: String) async throws -> [String: Any] {
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

    static var userAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return "NotchFlow/\(version)"
    }

    static func parseRetryAfter(_ raw: String?) -> TimeInterval? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if let seconds = TimeInterval(raw) {
            return max(seconds, 0)
        }
        return nil
    }
}

enum AgentUsageKeychain {
    typealias FetchError = AgentUsageClient.FetchError

    /// Reads another app's generic password. `nil` means no item; a denied prompt throws.
    static func copyGenericPassword(
        service: String,
        account: String,
        allowPrompt: Bool,
        provider: String
    ) throws -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if !allowPrompt {
            KeychainAccessPrompt.suppress(in: &query)
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

    static func secretFingerprint(_ refreshToken: String) -> String {
        let digest = SHA256.hash(data: Data(refreshToken.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

enum KeychainAccessPrompt {
    /// Suppresses the login-keychain password dialog for another app's item.
    /// `LAContext.interactionNotAllowed` does not. `kSecUseAuthenticationUIFail`
    /// does, and its value is `u_AuthUIF`; the symbol itself is deprecated.
    static func suppress(in query: inout [String: Any]) {
        query[kSecUseAuthenticationUI as String] = "u_AuthUIF"
    }
}
