import CommonCrypto
import CryptoKit
import Foundation
import LocalAuthentication
import Security
import SQLite3

/// Reads Claude Desktop's current access token. The refresh token is never decoded:
/// Anthropic rotates it, and using Desktop's copy would sign the app out.
enum ClaudeDesktopCredentials {
    struct Login: Equatable, Sendable {
        var accessToken: String
        var planName: String?
    }

    enum LoadError: Error, Equatable {
        case notFound
        case needsKeychainAccess
        case expired
        case unreadable
    }

    enum Selection: Equatable {
        case available(Login)
        case expired
        case notFound
    }

    private static let safeStorageService = "Claude Safe Storage"
    private static let safeStorageAccount = "Claude Key"
    private static let cacheV1Key = "oauth:tokenCache"
    private static let cacheV2Key = "oauth:tokenCacheV2"
    private static let apiHost = "https://api.anthropic.com"
    private static let usageScope = "user:profile"
    private static let inferenceScope = "user:inference"
    private static let productionClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let expirySafetyMargin: TimeInterval = 2 * 60
    private static let cookieHosts = [".claude.ai", "claude.ai"]
    private static var didPromptForKeychain = false

    static var hasCredentialMaterial: Bool {
        guard let root = readConfig() else { return false }
        return nonEmptyString(root[cacheV2Key]) != nil || nonEmptyString(root[cacheV1Key]) != nil
    }

    static func load(allowKeychainPrompt: Bool) throws -> Login {
        do {
            return try loadUnlocked(allowPrompt: false)
        } catch LoadError.needsKeychainAccess {
            let shouldPrompt = allowKeychainPrompt || !didPromptForKeychain
            guard shouldPrompt else { throw LoadError.needsKeychainAccess }
            didPromptForKeychain = true
            return try loadUnlocked(allowPrompt: true)
        }
    }

    static func select(
        v2: [String: Any]?,
        v1: [String: Any]?,
        organization: String?,
        accountUUID: String?,
        now: Date = Date()
    ) -> Selection {
        let v2Entries = normalizedCache(v2, activeAccountUUID: accountUUID)
        let v1Entries = normalizedCache(v1, activeAccountUUID: accountUUID)
            .filter { v2Entries[$0.key] == nil }
        let v2Pick = pick(in: v2Entries, organization: organization, now: now)
        if case .available = v2Pick { return v2Pick }
        let v1Pick = pick(in: v1Entries, organization: organization, now: now)
        if case .available = v1Pick { return v1Pick }
        if v2Pick == .expired || v1Pick == .expired { return .expired }
        return .notFound
    }

    static func deriveKey(password: String) -> Data? {
        let passwordData = Data(password.utf8)
        let salt = Data("saltysalt".utf8)
        var key = Data(count: kCCKeySizeAES128)
        let keyCount = key.count
        let status = key.withUnsafeMutableBytes { keyBytes in
            passwordData.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: Int8.self).baseAddress,
                        passwordData.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        1003,
                        keyBytes.bindMemory(to: UInt8.self).baseAddress,
                        keyCount
                    )
                }
            }
        }
        return status == kCCSuccess ? key : nil
    }

    static func decrypt(_ encrypted: Data, key: Data) -> Data? {
        guard encrypted.count > 3,
              encrypted.prefix(3) == Data("v10".utf8),
              key.count == kCCKeySizeAES128 else {
            return nil
        }
        let payload = encrypted.dropFirst(3)
        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        var output = Data(count: payload.count + kCCBlockSizeAES128)
        var outputLength = 0
        let outputCapacity = output.count
        let status = output.withUnsafeMutableBytes { outputBytes in
            payload.withUnsafeBytes { payloadBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            payloadBytes.baseAddress,
                            payload.count,
                            outputBytes.baseAddress,
                            outputCapacity,
                            &outputLength
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        output.count = outputLength
        return output
    }

    private static func loadUnlocked(allowPrompt: Bool) throws -> Login {
        guard hasCredentialMaterial, let root = readConfig() else {
            throw LoadError.notFound
        }
        guard let password = try safeStoragePassword(allowPrompt: allowPrompt) else {
            throw LoadError.notFound
        }
        guard let key = deriveKey(password: password) else {
            throw LoadError.unreadable
        }
        let caches: (v2: [String: Any]?, v1: [String: Any]?)
        do {
            caches = (
                try decodeCache(root[cacheV2Key], key: key),
                try decodeCache(root[cacheV1Key], key: key)
            )
        } catch {
            throw LoadError.unreadable
        }
        let organization = activeOrganization(key: key) ?? profileOrganizationUUID()
        let account = nonEmptyString(root["lastKnownAccountUuid"])
        switch select(
            v2: caches.v2,
            v1: caches.v1,
            organization: organization,
            accountUUID: account,
            now: Date()
        ) {
        case .available(let login):
            return login
        case .expired:
            NotchFlowLog.agents.info("Claude Desktop login expired")
            throw LoadError.expired
        case .notFound:
            NotchFlowLog.agents.info("Claude Desktop cache had no usable access token")
            throw LoadError.notFound
        }
    }

    private static func safeStoragePassword(allowPrompt: Bool) throws -> String? {
        if let password = try copySafeStoragePassword(account: safeStorageAccount, allowPrompt: allowPrompt) {
            return password
        }
        return try copySafeStoragePassword(account: nil, allowPrompt: allowPrompt)
    }

    /// `nil` means this query found no item. A Keychain prompt denial throws.
    private static func copySafeStoragePassword(account: String?, allowPrompt: Bool) throws -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: safeStorageService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let account {
            query[kSecAttrAccount as String] = account
        }
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
            throw LoadError.needsKeychainAccess
        default:
            NotchFlowLog.agents.info("Claude Desktop keychain status \(status, privacy: .public)")
            throw LoadError.unreadable
        }
    }

    private static func decodeCache(_ stored: Any?, key: Data) throws -> [String: Any]? {
        guard let base64 = nonEmptyString(stored) else { return nil }
        guard let encrypted = Data(base64Encoded: base64),
              let plaintext = decrypt(encrypted, key: key),
              let object = try JSONSerialization.jsonObject(with: plaintext) as? [String: Any] else {
            throw LoadError.unreadable
        }
        return object
    }

    private static func activeOrganization(key: Data) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let paths = [
            home.appendingPathComponent("Library/Application Support/Claude/Cookies"),
            home.appendingPathComponent("Library/Application Support/Claude/Network/Cookies"),
        ]
        for url in paths where FileManager.default.fileExists(atPath: url.path) {
            for host in cookieHosts {
                guard let stored = cookiePayload(database: url, host: host) else { continue }
                let value: Data
                if stored.encrypted {
                    guard let decrypted = decrypt(stored.data, key: key) else { continue }
                    let hostHash = Data(SHA256.hash(data: Data(host.utf8)))
                    guard decrypted.starts(with: hostHash) else { continue }
                    value = decrypted.dropFirst(hostHash.count)
                } else {
                    value = stored.data
                }
                if let organization = String(data: value, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   UUID(uuidString: organization) != nil {
                    return organization.lowercased()
                }
            }
        }
        return nil
    }

    private static func cookiePayload(database: URL, host: String) -> (encrypted: Bool, data: Data)? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            return nil
        }
        defer { sqlite3_close(db) }
        let sql = """
        SELECT CASE
          WHEN length(value) > 0 THEN 'plain:' || hex(CAST(value AS BLOB))
          ELSE 'encrypted:' || hex(encrypted_value)
        END
        FROM cookies
        WHERE name = 'lastActiveOrg' AND host_key = ?
        ORDER BY last_update_utc DESC
        LIMIT 1;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        let destructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, host, -1, destructor)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let cString = sqlite3_column_text(statement, 0) else {
            return nil
        }
        let encoded = String(cString: cString)
        guard let separator = encoded.firstIndex(of: ":"),
              let data = Data(hexString: String(encoded[encoded.index(after: separator)...])) else {
            return nil
        }
        return (String(encoded[..<separator]) == "encrypted", data)
    }

    private static func profileOrganizationUUID() -> String? {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = root["oauthAccount"] as? [String: Any],
              let organization = nonEmptyString(account["organizationUuid"]),
              UUID(uuidString: organization) != nil else {
            return nil
        }
        return organization.lowercased()
    }

    private static func readConfig() -> [String: Any]? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/config.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return root
    }

    private struct CacheKey: Hashable {
        var clientID: String
        var organization: String
        var scopes: [String]
    }

    private struct Candidate {
        var login: Login
        var rank: (Int, Int, Int, Double)
    }

    private static func pick(
        in cache: [CacheKey: Any],
        organization: String?,
        now: Date
    ) -> Selection {
        let wanted = organization?.lowercased()
        var available: [Candidate] = []
        var sawExpired = false
        let cutoff = now.timeIntervalSince1970 * 1000 + expirySafetyMargin * 1000
        for (key, raw) in cache {
            guard key.scopes.contains(usageScope) else { continue }
            if let wanted, key.organization != wanted { continue }
            guard !(raw is NSNull) else { continue }
            guard let entry = raw as? [String: Any],
                  let token = nonEmptyString(entry["token"]),
                  let expiresAt = number(entry["expiresAt"]) else {
                continue
            }
            guard expiresAt > cutoff else {
                sawExpired = true
                continue
            }
            let scopes = key.scopes
            let fullScope = scopes.contains(usageScope) && scopes.contains(inferenceScope)
            let production = key.clientID == productionClientID
            available.append(Candidate(
                login: Login(
                    accessToken: token,
                    planName: AgentUsageClient.claudePlanName(
                        subscriptionType: entry["subscriptionType"] as? String,
                        rateLimitTier: entry["rateLimitTier"] as? String
                    )
                ),
                rank: (
                    production && fullScope ? 1 : 0,
                    fullScope ? 1 : 0,
                    scopes.count,
                    expiresAt
                )
            ))
        }
        if let best = available.max(by: { $0.rank < $1.rank }) {
            return .available(best.login)
        }
        return sawExpired ? .expired : .notFound
    }

    /// Desktop migrates keys to `acct:<user>|<legacy>`. A scoped entry replaces its legacy alias.
    private static func normalizedCache(
        _ cache: [String: Any]?,
        activeAccountUUID: String?
    ) -> [CacheKey: Any] {
        guard let cache else { return [:] }
        var legacy: [CacheKey: Any] = [:]
        var scoped: [CacheKey: Any] = [:]
        for (rawKey, entry) in cache {
            let isScoped = rawKey.hasPrefix("acct:")
            var key = rawKey
            if isScoped {
                guard let separator = rawKey.firstIndex(of: "|"),
                      rawKey.distance(from: rawKey.startIndex, to: separator) > 5,
                      let owner = UUID(uuidString: String(rawKey[rawKey.index(rawKey.startIndex, offsetBy: 5)..<separator])),
                      let activeAccountUUID,
                      let active = UUID(uuidString: activeAccountUUID),
                      owner == active else {
                    continue
                }
                key = String(rawKey[rawKey.index(after: separator)...])
            }
            guard let parsed = parseCacheKey(key) else { continue }
            if isScoped {
                scoped[parsed] = entry
            } else {
                legacy[parsed] = entry
            }
        }
        return legacy.merging(scoped) { _, scopedEntry in scopedEntry }
    }

    private static func parseCacheKey(_ value: String) -> CacheKey? {
        let marker = ":\(apiHost):"
        guard let markerRange = value.range(of: marker) else { return nil }
        let prefix = value[..<markerRange.lowerBound]
        guard let firstColon = prefix.firstIndex(of: ":") else { return nil }
        let clientID = String(prefix[..<firstColon]).lowercased()
        let organization = String(prefix[prefix.index(after: firstColon)...]).lowercased()
        guard UUID(uuidString: clientID) != nil, UUID(uuidString: organization) != nil else {
            return nil
        }
        let scopes = value[markerRange.upperBound...]
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        return CacheKey(clientID: clientID, organization: organization, scopes: scopes)
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as Double: return number
        case let number as Int: return Double(number)
        case let number as NSNumber: return number.doubleValue
        default: return nil
        }
    }
}

private extension Data {
    init?(hexString: String) {
        let hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hex.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
