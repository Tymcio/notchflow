import Foundation

enum AgentUsageTightness: Equatable, Sendable {
    case normal
    case warning
    case critical
}

struct AgentUsageWindow: Equatable, Sendable {
    var usedPercent: Double
    var resetsAt: Date?

    var remainingPercent: Double {
        min(100, max(0, 100 - usedPercent))
    }

    var tightness: AgentUsageTightness {
        if usedPercent >= 95 { return .critical }
        if usedPercent >= 80 { return .warning }
        return .normal
    }
}

enum AgentUsageStatus: Equatable, Sendable {
    case ready
    case signedOut
    case needsKeychainAccess
    case loginExpired
    case rateLimited
    case unavailable
}

struct AgentUsageSnapshot: Equatable, Sendable {
    var agent: AgentKind
    var planName: String?
    var fiveHour: AgentUsageWindow?
    var sevenDay: AgentUsageWindow?
    var extra: AgentUsageWindow?
    var fetchedAt: Date
    var status: AgentUsageStatus

    var hasMeters: Bool {
        fiveHour != nil || sevenDay != nil || extra != nil
    }

    /// The window closest to the cap — what you glance at in the idle wing.
    var tightestWindow: AgentUsageWindow? {
        [fiveHour, sevenDay, extra]
            .compactMap { $0 }
            .max { $0.usedPercent < $1.usedPercent }
    }
}

struct AgentUsageIdleHint: Equatable, Sendable {
    var remainingPercent: Int
    var tightness: AgentUsageTightness
}

enum AgentUsageParser {
    static func parseClaude(_ json: [String: Any], fetchedAt: Date = Date()) -> AgentUsageSnapshot {
        AgentUsageSnapshot(
            agent: .claude,
            planName: nil,
            fiveHour: parseClaudeWindow(json["five_hour"]),
            sevenDay: parseClaudeWindow(json["seven_day"]),
            extra: parseClaudeExtra(json["extra_usage"]),
            fetchedAt: fetchedAt,
            status: .ready
        )
    }

    static func parseCodex(_ json: [String: Any], fetchedAt: Date = Date()) -> AgentUsageSnapshot {
        let rateLimit = json["rate_limit"] as? [String: Any] ?? json
        let primary = parseCodexWindow(rateLimit["primary_window"] ?? json["five_hour"] ?? json["five_hour_limit"])
        let secondary = parseCodexWindow(rateLimit["secondary_window"] ?? json["weekly"] ?? json["weekly_limit"])
        let classified = classifyCodexWindows(primary: primary, secondary: secondary)
        let plan = stringValue(json["plan_type"]) ?? stringValue(json["plan"])
        return AgentUsageSnapshot(
            agent: .codex,
            planName: plan,
            fiveHour: classified.fiveHour,
            sevenDay: classified.sevenDay,
            extra: nil,
            fetchedAt: fetchedAt,
            status: .ready
        )
    }

    static func idleHint(from snapshot: AgentUsageSnapshot?) -> AgentUsageIdleHint? {
        guard let snapshot, snapshot.status == .ready || snapshot.hasMeters,
              let window = snapshot.tightestWindow else { return nil }
        return AgentUsageIdleHint(
            remainingPercent: Int(window.remainingPercent.rounded()),
            tightness: window.tightness
        )
    }

    static func coercePercent(_ any: Any?) -> Double? {
        guard let value = coerceDouble(any) else { return nil }
        if value.isNaN || value.isInfinite { return nil }
        return min(100, max(0, value))
    }

    static func parseResetDate(_ any: Any?) -> Date? {
        if let date = any as? Date { return date }
        if let value = coerceDouble(any) {
            if value > 1_000_000_000_000 {
                return Date(timeIntervalSince1970: value / 1000)
            }
            if value > 1_000_000_000 {
                return Date(timeIntervalSince1970: value)
            }
        }
        guard let raw = any as? String, !raw.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: raw)
    }

    private static func parseClaudeWindow(_ any: Any?) -> AgentUsageWindow? {
        guard let object = any as? [String: Any] else { return nil }
        let percent = coercePercent(object["utilization"] ?? object["used_percentage"] ?? object["used_percent"])
        guard let percent else { return nil }
        return AgentUsageWindow(
            usedPercent: percent,
            resetsAt: parseResetDate(object["resets_at"] ?? object["reset_at"])
        )
    }

    private static func parseClaudeExtra(_ any: Any?) -> AgentUsageWindow? {
        guard let object = any as? [String: Any] else { return nil }
        let enabled = boolValue(object["is_enabled"])
        guard enabled else { return nil }
        var percent = coercePercent(object["utilization"])
        if percent == nil,
           let used = coerceDouble(object["used_credits"]),
           let limit = coerceDouble(object["monthly_limit"]),
           limit > 0 {
            percent = min(100, max(0, used / limit * 100))
        }
        guard let percent else { return nil }
        return AgentUsageWindow(usedPercent: percent, resetsAt: nil)
    }

    private static func parseCodexWindow(_ any: Any?) -> (window: AgentUsageWindow, seconds: Double?)? {
        guard let object = any as? [String: Any] else { return nil }
        let percent = coercePercent(object["used_percent"] ?? object["used_percentage"] ?? object["utilization"])
        guard let percent else { return nil }
        let seconds = coerceDouble(object["limit_window_seconds"] ?? object["window_seconds"])
        let reset = parseResetDate(object["reset_at"] ?? object["resets_at"])
            ?? relativeReset(object["reset_after_seconds"])
        return (AgentUsageWindow(usedPercent: percent, resetsAt: reset), seconds)
    }

    private static func classifyCodexWindows(
        primary: (window: AgentUsageWindow, seconds: Double?)?,
        secondary: (window: AgentUsageWindow, seconds: Double?)?
    ) -> (fiveHour: AgentUsageWindow?, sevenDay: AgentUsageWindow?) {
        var fiveHour: AgentUsageWindow?
        var sevenDay: AgentUsageWindow?
        for candidate in [primary, secondary] {
            guard let candidate else { continue }
            switch classifyWindowDuration(candidate.seconds) {
            case .fiveHour:
                if fiveHour == nil { fiveHour = candidate.window }
            case .sevenDay:
                if sevenDay == nil { sevenDay = candidate.window }
            case .unknown:
                break
            }
        }
        if fiveHour == nil { fiveHour = primary?.window }
        if sevenDay == nil { sevenDay = secondary?.window }
        return (fiveHour, sevenDay)
    }

    private enum WindowKind {
        case fiveHour
        case sevenDay
        case unknown
    }

    private static func classifyWindowDuration(_ seconds: Double?) -> WindowKind {
        guard let seconds, seconds > 0 else { return .unknown }
        // 5h = 18_000, 7d = 604_800. Match with a wide band so swapped slots still work.
        if seconds >= 3 * 3600 && seconds <= 9 * 3600 { return .fiveHour }
        if seconds >= 5 * 86_400 && seconds <= 9 * 86_400 { return .sevenDay }
        return .unknown
    }

    private static func relativeReset(_ any: Any?) -> Date? {
        guard let seconds = coerceDouble(any), seconds > 0 else { return nil }
        return Date().addingTimeInterval(seconds)
    }

    private static func coerceDouble(_ any: Any?) -> Double? {
        switch any {
        case let value as Double: return value
        case let value as Float: return Double(value)
        case let value as Int: return Double(value)
        case let value as Int64: return Double(value)
        case let value as NSNumber: return value.doubleValue
        case let value as String: return Double(value)
        default: return nil
        }
    }

    private static func stringValue(_ any: Any?) -> String? {
        guard let string = any as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func boolValue(_ any: Any?) -> Bool {
        if let bool = any as? Bool { return bool }
        if let number = any as? NSNumber { return number.boolValue }
        if let string = any as? String {
            return ["1", "true", "yes"].contains(string.lowercased())
        }
        return false
    }
}
