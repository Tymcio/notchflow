import Foundation

/// Grok Bot desktop login from its encrypted `sand-secrets.json`.
enum GrokBotUsageProvider: AgentUsageProvider {
    typealias FetchError = AgentUsageClient.FetchError

    static let agent: AgentKind = .grokbot

    static var hasCredentials: Bool {
        FileManager.default.fileExists(atPath: secretsURL.path)
    }

    static func fetch(allowKeychainPrompt: Bool) async throws -> AgentUsageSnapshot {
        let session = try loadSession(allowKeychainPrompt: allowKeychainPrompt)
        let cached = cachedSession(fingerprint: session.fingerprint)
        let accessToken = cached?.accessToken ?? session.accessToken
        let refreshToken = cached?.refreshToken ?? session.refreshToken
        let json: [String: Any]
        do {
            json = try await postUsage(token: accessToken)
        } catch FetchError.signedOut {
            let refreshed = try await refresh(refreshToken: refreshToken)
            storeSession(fingerprint: session.fingerprint, accessToken: refreshed.accessToken, refreshToken: refreshed.refreshToken)
            do {
                json = try await postUsage(token: refreshed.accessToken)
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

    // MARK: - Credentials

    private struct Session {
        var accessToken: String
        var refreshToken: String
        var fingerprint: String
    }

    private static var secretsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Grok Bot/sand-secrets.json")
    }

    /// Tokens NotchFlow refreshed itself. Memory only; never written to disk.
    private static let rotated = RotatedTokenCache()

    private static func loadSession(allowKeychainPrompt: Bool) throws -> Session {
        guard let data = try? Data(contentsOf: secretsURL) else {
            throw FetchError.signedOut
        }
        let password: String
        do {
            guard let found = try safeStoragePassword(allowPrompt: allowKeychainPrompt) else {
                throw FetchError.signedOut
            }
            password = found
        } catch FetchError.needsKeychainAccess {
            throw FetchError.needsKeychainAccess
        }
        guard let key = ClaudeDesktopCredentials.deriveKey(password: password),
              let session = decodeSession(data, key: key) else {
            throw FetchError.invalidResponse
        }
        return session
    }

    static func decodeSecrets(_ data: Data, password: String) -> (accessToken: String, refreshToken: String)? {
        guard let key = ClaudeDesktopCredentials.deriveKey(password: password),
              let session = decodeSession(data, key: key) else {
            return nil
        }
        return (session.accessToken, session.refreshToken)
    }

    private static func decodeSession(_ data: Data, key: Data) -> Session? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accounts = accountsObject(root["cursor-accounts"]),
              let active = accounts["active"] as? String,
              let map = accounts["accounts"] as? [String: Any],
              let entry = map[active] as? [String: Any],
              let access = decryptField(entry["cursor-access-token"], key: key),
              let refresh = decryptField(entry["cursor-refresh-token"], key: key),
              !access.isEmpty, !refresh.isEmpty else {
            return nil
        }
        return Session(
            accessToken: access,
            refreshToken: refresh,
            fingerprint: AgentUsageKeychain.secretFingerprint(refresh)
        )
    }

    private static func accountsObject(_ value: Any?) -> [String: Any]? {
        if let object = value as? [String: Any] { return object }
        guard let text = value as? String,
              let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private static func decryptField(_ value: Any?, key: Data) -> String? {
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

    private static func safeStoragePassword(allowPrompt: Bool) throws -> String? {
        try AgentUsageKeychain.copyGenericPassword(
            service: "Grok Bot Safe Storage",
            account: "Grok Bot Key",
            allowPrompt: allowPrompt,
            provider: "Grok Bot"
        )
    }

    /// NotchFlow's own rotated pair for this launch. The fingerprint is the refresh token
    /// still in Grok Bot's file.
    private static func cachedSession(fingerprint: String) -> RotatedTokenSession? {
        guard let session = rotated.session(matching: fingerprint),
              !session.accessToken.isEmpty,
              !session.refreshToken.isEmpty else {
            return nil
        }
        return session
    }

    private static func storeSession(fingerprint: String, accessToken: String, refreshToken: String) {
        rotated.store(RotatedTokenSession(
            fingerprint: fingerprint,
            accessToken: accessToken,
            refreshToken: refreshToken
        ))
    }

    private static func postUsage(token: String) async throws -> [String: Any] {
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
        request.setValue(AgentUsageHTTP.userAgent, forHTTPHeaderField: "User-Agent")
        return try await AgentUsageHTTP.perform(request, provider: "Grok Bot")
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
            json = try await AgentUsageHTTP.perform(request, provider: "Grok Bot")
        } catch FetchError.signedOut {
            throw FetchError.loginExpired
        }
        guard let access = json["access_token"] as? String, !access.isEmpty else {
            throw FetchError.invalidResponse
        }
        let rotated = (json["refresh_token"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? refreshToken
        return RefreshedToken(accessToken: access, refreshToken: rotated)
    }
}
