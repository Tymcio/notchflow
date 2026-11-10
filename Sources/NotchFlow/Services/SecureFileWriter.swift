import Darwin
import Foundation

/// Writes NotchFlow's own files: owner-only (0600), replaced atomically.
/// Do not use it for another tool's config; see `ExternalConfigFile`.
enum SecureFileWriter {
    static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: url.path
        )
    }
}

enum ExternalConfigError: LocalizedError, Equatable {
    /// The file exists but is not a JSON object. It is left untouched.
    case notJSONObject(path: String)
    /// The owning tool kept rewriting the file while NotchFlow tried to update it.
    case changedDuringWrite(path: String)

    var errorDescription: String? {
        switch self {
        case .notJSONObject(let path):
            locFormat("%@ is not a valid JSON settings file. NotchFlow left it unchanged. Fix or remove it, then connect agents again.", path)
        case .changedDuringWrite(let path):
            locFormat("%@ changed while NotchFlow was updating it. Try again in a moment.", path)
        }
    }
}

/// Edits JSON config files that belong to other tools (Claude Code, Cursor, Grok).
///
/// - Follows symlinks and writes the real file, so a symlinked `settings.json` stays a symlink.
/// - Keeps the file's existing permissions (new files are created owner-only).
/// - Saves `<file>.notchflow-backup` once, before NotchFlow first changes the file.
/// - Refuses to touch a file that exists but is not a JSON object.
/// - Re-reads the file just before the atomic rename and retries if the owning tool changed it.
enum ExternalConfigFile {
    static let backupSuffix = ".notchflow-backup"
    private static let newFileMode: mode_t = 0o600

    /// Follows a chain of symlinks to the file that actually holds the content.
    static func resolvedTarget(for url: URL) -> URL {
        var current = url.standardizedFileURL
        for _ in 0..<32 {
            guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: current.path) else {
                return current
            }
            let next = destination.hasPrefix("/")
                ? URL(fileURLWithPath: destination)
                : current.deletingLastPathComponent().appendingPathComponent(destination)
            current = next.standardizedFileURL
        }
        return current
    }

    static func backupURL(for url: URL) -> URL {
        URL(fileURLWithPath: url.standardizedFileURL.path + backupSuffix)
    }

    /// Reads, transforms and rewrites a JSON-object config file.
    ///
    /// - Parameters:
    ///   - createIfMissing: when false and the file does not exist, nothing is written.
    /// - Returns: true when the file was written.
    @discardableResult
    static func updateJSONObject(
        at url: URL,
        createIfMissing: Bool = true,
        attempts: Int = 3,
        _ transform: (inout [String: Any]) throws -> Void
    ) throws -> Bool {
        let target = resolvedTarget(for: url)
        for _ in 0..<max(attempts, 1) {
            let original = try readIfPresent(target)
            if original == nil, !createIfMissing { return false }

            var root = try parseObject(original, displayPath: url.path)
            try transform(&root)
            let output = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
            if let original, original == output { return false }

            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let mode = existingMode(of: target) ?? newFileMode
            if let original {
                try writeBackupIfNeeded(original, for: url, mode: mode)
            }
            if try replace(target, with: output, mode: mode, expecting: original) {
                return true
            }
        }
        throw ExternalConfigError.changedDuringWrite(path: url.path)
    }

    /// `[:]` for a missing or blank file; throws for anything that is not a JSON object.
    static func parseObject(_ data: Data?, displayPath: String) throws -> [String: Any] {
        guard let data else { return [:] }
        let blank = data.allSatisfy { $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }
        if blank { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any] else {
            throw ExternalConfigError.notJSONObject(path: displayPath)
        }
        return root
    }

    // MARK: - File operations

    private static func readIfPresent(_ url: URL) throws -> Data? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return nil
        }
        if isDirectory.boolValue {
            throw ExternalConfigError.notJSONObject(path: url.path)
        }
        // A file we cannot read must not be treated as missing and overwritten.
        return try Data(contentsOf: url)
    }

    private static func existingMode(of url: URL) -> mode_t? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let permissions = attributes[.posixPermissions] as? NSNumber else {
            return nil
        }
        return mode_t(permissions.uint16Value) & 0o7777
    }

    private static func writeBackupIfNeeded(_ original: Data, for url: URL, mode: mode_t) throws {
        let backup = backupURL(for: url)
        if FileManager.default.fileExists(atPath: backup.path) { return }
        let descriptor = open(backup.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode)
        if descriptor < 0 {
            if errno == EEXIST { return }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        do {
            try writeAll(original, to: descriptor)
            _ = fchmod(descriptor, mode)
            close(descriptor)
        } catch {
            close(descriptor)
            unlink(backup.path)
            throw error
        }
    }

    /// Writes a temp file next to `target`, then renames it over `target` if the file still
    /// holds `expecting`. Returns false (and writes nothing) when it changed in between.
    private static func replace(_ target: URL, with data: Data, mode: mode_t, expecting: Data?) throws -> Bool {
        let directory = target.deletingLastPathComponent()
        let temp = directory.appendingPathComponent(".\(target.lastPathComponent).notchflow-\(UUID().uuidString).tmp")
        let descriptor = open(temp.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        do {
            try writeAll(data, to: descriptor)
            // open() applies the umask; set the exact mode the file had before.
            guard fchmod(descriptor, mode) == 0, fsync(descriptor) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            close(descriptor)
        } catch {
            close(descriptor)
            unlink(temp.path)
            throw error
        }

        let current = try? readIfPresent(target)
        guard current == expecting else {
            unlink(temp.path)
            return false
        }
        guard rename(temp.path, target.path) == 0 else {
            let code = errno
            unlink(temp.path)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        return true
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { buffer in
            guard var pointer = buffer.baseAddress else { return }
            var remaining = buffer.count
            while remaining > 0 {
                let written = Darwin.write(descriptor, pointer, remaining)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                remaining -= written
                pointer = pointer.advanced(by: written)
            }
        }
    }
}
