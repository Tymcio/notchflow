import Foundation
import os

/// Why an AppleScript did not produce a result.
struct AppleScriptFailure: Error, Sendable, Equatable {
    let number: Int
    let message: String

    /// -1743: the user has not allowed NotchFlow to control that app (Automation).
    var isNotAuthorized: Bool { number == -1743 }
}

/// Runs every `NSAppleScript` in the app on one serial queue.
///
/// `NSAppleScript` is not thread-safe, so it must never run concurrently or from arbitrary
/// task-pool threads. Compiled scripts are cached for sources that run repeatedly (polling,
/// artwork) so each run only sends Apple Events instead of recompiling.
final class AppleScriptExecutor: @unchecked Sendable {
    static let shared = AppleScriptExecutor()

    /// The only place `NSAppleScript` is touched. Owns `compiledScripts` and `lastLoggedFailure`.
    private let queue = DispatchQueue(label: "NotchFlow.AppleScript", qos: .userInitiated)
    private var compiledScripts: [String: NSAppleScript] = [:]
    private var lastLoggedFailure: [String: Int] = [:]

    /// Executes `source` and converts the result on the script queue.
    func run<T: Sendable>(
        _ source: String,
        cacheCompiled: Bool = false,
        transform: @escaping @Sendable (NSAppleEventDescriptor) -> T
    ) async -> Result<T, AppleScriptFailure> {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.execute(source, cacheCompiled: cacheCompiled).map(transform))
            }
        }
    }

    /// Fire-and-forget execution for transport commands; failures are logged.
    func runDetached(_ source: String) {
        queue.async {
            _ = self.execute(source, cacheCompiled: false)
        }
    }

    // MARK: - Script queue only

    private func execute(_ source: String, cacheCompiled: Bool) -> Result<NSAppleEventDescriptor, AppleScriptFailure> {
        dispatchPrecondition(condition: .onQueue(queue))

        let script: NSAppleScript
        if cacheCompiled, let cached = compiledScripts[source] {
            script = cached
        } else {
            guard let created = NSAppleScript(source: source) else {
                return .failure(log(AppleScriptFailure(number: -2700, message: "Invalid script source"), source: source))
            }
            if cacheCompiled {
                var compileError: NSDictionary?
                guard created.compileAndReturnError(&compileError) else {
                    return .failure(log(failure(from: compileError), source: source))
                }
                compiledScripts[source] = created
            }
            script = created
        }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            return .failure(log(failure(from: error), source: source))
        }
        lastLoggedFailure[source] = nil
        return .success(result)
    }

    private func failure(from info: NSDictionary?) -> AppleScriptFailure {
        AppleScriptFailure(
            number: (info?[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0,
            message: info?[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
        )
    }

    /// Logs a failure once per script until it changes or the script succeeds again,
    /// so a polling script without Automation permission doesn't flood the log.
    private func log(_ failure: AppleScriptFailure, source: String) -> AppleScriptFailure {
        guard lastLoggedFailure[source] != failure.number else { return failure }
        lastLoggedFailure[source] = failure.number
        let target = Self.targetApplication(in: source)
        if failure.isNotAuthorized {
            NotchFlowLog.media.notice(
                "AppleScript to \(target, privacy: .public) not authorized (Automation permission missing)"
            )
        } else {
            NotchFlowLog.media.error(
                "AppleScript to \(target, privacy: .public) failed (\(failure.number, privacy: .public)): \(failure.message, privacy: .private)"
            )
        }
        return failure
    }

    private static func targetApplication(in source: String) -> String {
        guard let start = source.range(of: "application \"")?.upperBound,
              let end = source[start...].firstIndex(of: "\"") else { return "unknown app" }
        return String(source[start..<end])
    }
}
