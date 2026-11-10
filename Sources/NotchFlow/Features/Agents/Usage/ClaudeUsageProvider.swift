import Foundation
import os
import Security

/// Claude Code (CLI file or Keychain item) with Claude Desktop as a fallback.
enum ClaudeUsageProvider: AgentUsageProvider {
    typealias FetchError = AgentUsageClient.FetchError

    static let agent: AgentKind = .claude

    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let beta = "oauth-2025-04-20"
    private static let keychainService = "Claude Code-credentials"

    static var hasCredentials: Bool {
        switch cliCredentials(allowKeychainPrompt: false) {
        case .ready, .needsKeychainAccess:
            return true
        case .missing:
            return ClaudeDesktopCredentials.hasCredentialMaterial
        }
    }

    static func fetch(allowKeychainPrompt: Bool) async throws -> AgentUsageSnapshot {
        var cli = cliCredentials(allowKeychainPrompt: allowKeychainPrompt)
        if case .ready(let creds) = cli {
            do {
                return try await requestUsage(creds, source: "cli")
            } catch FetchError.signedOut {
                NotchFlowLog.agents.info("Claude CLI usage unauthorized, trying Desktop login")
                invalidateKeychainCache()
                cli = cliCredentials(allowKeychainPrompt: false)
                if case .ready(let refreshed) = cli, refreshed.accessToken != creds.accessToken {
                    do {
                        return try await requestUsage(refreshed, source: "cli")
                    } catch FetchError.signedOut {
                        cli = .missing
                    }
                }
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
                if case .needsKeychainAccess = cli {
                    throw FetchError.needsKeychainAccess
                }
                throw FetchError.signedOut
            case .unreadable:
                if case .needsKeychainAccess = cli {
                    throw FetchError.needsKeychainAccess
                }
                throw FetchError.invalidResponse
            }
        } catch {
            throw FetchError.invalidResponse
        }

        do {
            return try await requestUsage(
                Credentials(accessToken: desktop.accessToken, planName: desktop.planName, expiresAt: nil),
                source: "desktop"
            )
        } catch FetchError.signedOut {
            throw FetchError.loginExpired
        }
    }

    private static func requestUsage(_ creds: Credentials, source: String) async throws -> AgentUsageSnapshot {
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(beta, forHTTPHeaderField: "anthropic-beta")
        request.setValue(AgentUsageHTTP.userAgent, forHTTPHeaderField: "User-Agent")

        let json = try await AgentUsageHTTP.perform(request, provider: "Claude")
        var snapshot = AgentUsageParser.parseClaude(json)
        snapshot.planName = creds.planName
        snapshot.status = snapshot.hasMeters ? .ready : .unavailable
        let fiveHour = snapshot.fiveHour.map { Int($0.remainingPercent.rounded()) } ?? -1
        let sevenDay = snapshot.sevenDay.map { Int($0.remainingPercent.rounded()) } ?? -1
        NotchFlowLog.agents.info("Claude usage source=\(source, privacy: .public) 5hLeft=\(fiveHour, privacy: .public) 7dLeft=\(sevenDay, privacy: .public)")
        return snapshot
    }

    // MARK: - Credentials

    private struct Credentials {
        let accessToken: String
        let planName: String?
        let expiresAt: Date?
    }

    private enum CLICredentials {
        case ready(Credentials)
        case needsKeychainAccess
        case missing
    }

    private enum KeychainSecret {
        case data(Data)
        case missing
        case interactionRequired
    }

    /// Last Claude Code secret read this process. Re-reading the login item on
    /// every session update raises the Keychain dialog again: Claude replaces
    /// the item when it refreshes the login, which drops "Always Allow".
    private struct KeychainCache: Sendable {
        var payload: Data?
        var needsUnlock = false
    }

    /// Touched from the monitor's credential check and from background fetches.
    private static let keychainCache = OSAllocatedUnfairLock(initialState: KeychainCache())

    private static var keychainNeedsUnlock: Bool {
        get { keychainCache.withLock { $0.needsUnlock } }
        set { keychainCache.withLock { $0.needsUnlock = newValue } }
    }

    private static func invalidateKeychainCache() {
        keychainCache.withLock { $0 = KeychainCache() }
    }

    private static func cliCredentials(allowKeychainPrompt: Bool) -> CLICredentials {
        guard let data = credentialData(allowKeychainPrompt: allowKeychainPrompt) else {
            return keychainNeedsUnlock ? .needsKeychainAccess : .missing
        }
        guard let creds = decodeCredentials(data) else { return .missing }
        if let expiresAt = creds.expiresAt, expiresAt <= Date() {
            return .missing
        }
        return .ready(creds)
    }

    private static func credentialData(allowKeychainPrompt: Bool) -> Data? {
        if let data = credentialsFileData() { return data }
        if let cached = freshKeychainPayload() { return cached }
        if !allowKeychainPrompt, keychainNeedsUnlock { return nil }

        switch copyKeychain(allowPrompt: allowKeychainPrompt) {
        case .data(let data):
            keychainCache.withLock { $0 = KeychainCache(payload: data, needsUnlock: false) }
            let fresh = freshKeychainPayload()
            if fresh == nil {
                // Expired or unreadable. Don't ask Keychain again until a manual refresh.
                keychainNeedsUnlock = true
            }
            return fresh
        case .missing:
            return nil
        case .interactionRequired:
            keychainNeedsUnlock = true
            return nil
        }
    }

    /// Keeps a granted secret until it expires so later polls do not touch Keychain.
    private static func freshKeychainPayload() -> Data? {
        guard let cached = keychainCache.withLock({ $0.payload }) else { return nil }
        guard let creds = decodeCredentials(cached) else { return nil }
        if let expiresAt = creds.expiresAt, expiresAt <= Date() { return nil }
        return cached
    }

    private static func credentialsFileData() -> Data? {
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

    private static func copyKeychain(allowPrompt: Bool) -> KeychainSecret {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        if !allowPrompt {
            KeychainAccessPrompt.suppress(in: &query)
        }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return .missing }
            return .data(data)
        case errSecItemNotFound:
            return .missing
        case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled:
            if allowPrompt {
                NotchFlowLog.agents.info("Claude Code keychain prompt was not granted (\(status, privacy: .public))")
            } else {
                NotchFlowLog.agents.info("Claude Code keychain needs access; prompt suppressed")
            }
            return .interactionRequired
        default:
            NotchFlowLog.agents.info("Claude Code keychain status \(status, privacy: .public)")
            return .missing
        }
    }

    static func parseCredentialFile(_ data: Data) -> (accessToken: String, planName: String?)? {
        guard let creds = decodeCredentials(data) else { return nil }
        return (creds.accessToken, creds.planName)
    }

    private static func decodeCredentials(_ data: Data) -> Credentials? {
        guard let root = jsonObject(from: data) else { return nil }
        let oauth = root["claudeAiOauth"] as? [String: Any] ?? root
        guard let token = oauth["accessToken"] as? String ?? oauth["access_token"] as? String,
              !token.isEmpty else {
            return nil
        }
        return Credentials(
            accessToken: token,
            planName: formatPlan(
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

    static func formatPlan(subscriptionType: String?, rateLimitTier: String?) -> String? {
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
}
