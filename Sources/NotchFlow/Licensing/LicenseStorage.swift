import Foundation

/// File-backed storage for license keys, activation IDs and the cached license status.
///
/// Licenses used to live in the login Keychain, but legacy Keychain items are bound to
/// the code signature of the app that created them. Release builds are signed with
/// "Developer ID", local builds with "Apple Development", so each build could not read
/// what the other wrote and silently fell back to the free tier. A plain 0600 file in
/// Application Support is shared by every build of the app.
///
/// The first time the file is missing, existing Keychain items are migrated once; after
/// that the Keychain is never consulted again (so deleted values cannot come back).
struct LicenseStorage {
    let fileURL: URL
    private let legacyKeychain: KeychainStore?
    private let legacyKeys: [String]

    init(fileURL: URL? = nil, legacyKeychain: KeychainStore? = nil, legacyKeys: [String] = []) {
        self.fileURL = fileURL ?? Self.defaultFileURL
        self.legacyKeychain = legacyKeychain
        self.legacyKeys = legacyKeys
        migrateFromKeychainIfNeeded()
    }

    static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchFlow/License/license.json")
    }

    func save(key: String, value: String) throws {
        try save(key: key, data: Data(value.utf8))
    }

    func save(key: String, data: Data) throws {
        var values = loadValues() ?? [:]
        values[key] = data.base64EncodedString()
        try writeValues(values)
    }

    func read(key: String) -> String? {
        guard let data = readData(key: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func readData(key: String) -> Data? {
        guard let encoded = loadValues()?[key] else { return nil }
        return Data(base64Encoded: encoded)
    }

    func delete(key: String) throws {
        var values = loadValues() ?? [:]
        values.removeValue(forKey: key)
        try writeValues(values)
        try? legacyKeychain?.delete(key: key)
    }

    private func loadValues() -> [String: String]? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }

    private func writeValues(_ values: [String: String]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try SecureFileWriter.write(try encoder.encode(values), to: fileURL)
    }

    private func migrateFromKeychainIfNeeded() {
        guard let legacyKeychain,
              !FileManager.default.fileExists(atPath: fileURL.path) else { return }

        var values: [String: String] = [:]
        for key in legacyKeys {
            if let data = legacyKeychain.readData(key: key) {
                values[key] = data.base64EncodedString()
            }
        }
        do {
            try writeValues(values)
            NotchFlowLog.license.info("Migrated \(values.count, privacy: .public) license values from Keychain")
        } catch {
            NotchFlowLog.license.error("License storage migration failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
