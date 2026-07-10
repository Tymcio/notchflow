import CryptoKit
import Foundation

enum APIAuth {
    private static let keychain = KeychainStore(service: "eu.notchflow.app.api")
    private static let tokenKey = "local_api_token"

    static func token() -> String {
        if let existing = keychain.read(key: tokenKey) {
            return existing
        }
        let key = SymmetricKey(size: .bits256)
        let generated = key.withUnsafeBytes { raw in
            Data(raw).base64EncodedString()
        }
        do {
            try keychain.save(key: tokenKey, value: generated)
        } catch {
            NotchFlowLog.api.error("Failed to persist API token: \(error.localizedDescription, privacy: .public)")
        }
        return generated
    }

    static func validate(_ headerValue: String?) -> Bool {
        guard let headerValue else { return false }
        let presented = headerValue.hasPrefix("Bearer ")
            ? String(headerValue.dropFirst("Bearer ".count))
            : headerValue
        return timingSafeCompare(presented, token())
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
