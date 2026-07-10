import CryptoKit
import Foundation

enum APIAuth {
    private static let keychain = KeychainStore(service: "eu.notchflow.app.api")
    private static let tokenKey = "local_api_token"

    static func token() -> String {
        if let existing = keychain.read(key: tokenKey) {
            return existing
        }
        let generated = UUID().uuidString + "-" + UUID().uuidString
        try? keychain.save(key: tokenKey, value: generated)
        return generated
    }

    static func validate(_ headerValue: String?) -> Bool {
        guard let headerValue else { return false }
        let token = headerValue.replacingOccurrences(of: "Bearer ", with: "")
        return token == self.token()
    }
}
