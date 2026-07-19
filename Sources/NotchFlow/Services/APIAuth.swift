import CryptoKit
import Foundation

enum APIAuthError: Error {
    case tokenPersistenceFailed
}

enum APIAuth {
    private static let keychain = KeychainStore(service: "eu.notchflow.app.api")
    private static let tokenKey = "local_api_token"
    private static var cachedToken: String?

    static func token() throws -> String {
        if let cachedToken {
            return cachedToken
        }
        if let existing = keychain.read(key: tokenKey) {
            cachedToken = existing
            persistTokenFile(existing)
            return existing
        }
        let key = SymmetricKey(size: .bits256)
        let generated = key.withUnsafeBytes { raw in
            Data(raw).base64EncodedString()
        }
        do {
            try keychain.save(key: tokenKey, value: generated)
            cachedToken = generated
            persistTokenFile(generated)
            return generated
        } catch {
            NotchFlowLog.api.error("Failed to persist API token: \(error.localizedDescription, privacy: .public)")
            throw APIAuthError.tokenPersistenceFailed
        }
    }

    /// Hook scripts (Agents addon) read the bearer token from this file.
    static var tokenFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchFlow/api-token")
    }

    private static func persistTokenFile(_ token: String) {
        let url = tokenFileURL
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try SecureFileWriter.write(Data(token.utf8), to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            NotchFlowLog.api.error("Failed to write API token file: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func validate(_ headerValue: String?) -> Bool {
        guard let headerValue else { return false }
        let presented = headerValue.hasPrefix("Bearer ")
            ? String(headerValue.dropFirst("Bearer ".count))
            : headerValue
        guard let expected = try? token() else { return false }
        return timingSafeCompare(presented, expected)
    }

    static func resolvedToken() -> String {
        (try? token()) ?? ""
    }

    private static func timingSafeCompare(_ lhs: String, _ rhs: String) -> Bool {
        let left = Data(lhs.utf8)
        let right = Data(rhs.utf8)
        guard left.count == right.count else { return false }

        var difference: UInt8 = 0
        for index in left.indices {
            difference |= left[index] ^ right[index]
        }
        return difference == 0
    }
}
