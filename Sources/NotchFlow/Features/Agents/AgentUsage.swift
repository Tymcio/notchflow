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

struct AgentUsageMeter: Equatable, Sendable {
    /// Localization key shown beside the bar.
    var label: String
    var window: AgentUsageWindow
}

struct AgentUsageSnapshot: Equatable, Sendable {
    var agent: AgentKind
    var planName: String?
    var fiveHour: AgentUsageWindow?
    var sevenDay: AgentUsageWindow?
    var extra: AgentUsageWindow?
    /// Named meters for providers that are not 5-hour / 7-day windows, such as Cursor.
    var meters: [AgentUsageMeter] = []
    var fetchedAt: Date
    var status: AgentUsageStatus

    var hasMeters: Bool {
        fiveHour != nil || sevenDay != nil || extra != nil || !meters.isEmpty
    }

    /// The window closest to the cap — what you glance at in the idle wing.
    var tightestWindow: AgentUsageWindow? {
        ([fiveHour, sevenDay, extra].compactMap { $0 } + meters.map(\.window))
            .max { $0.usedPercent < $1.usedPercent }
    }
}

struct AgentUsageIdleHint: Equatable, Sendable {
    var remainingPercent: Int
    var tightness: AgentUsageTightness
}

enum AgentUsageResetCopy {
    /// Localized “resets in …” line for a usage window. Nil resets stay hidden by the caller.
    static func phrase(until reset: Date, now: Date = Date()) -> String {
        let locale = Locale(identifier: LanguageResolver.languageCode)
        if let duration = duration(until: reset, now: now, locale: locale) {
            return locFormat("Resets in %@", duration)
        }
        if reset.timeIntervalSince(now) <= 0 {
            return loc("Resets now")
        }
        return loc("Resets in less than a minute")
    }

    static func duration(until reset: Date, now: Date, locale: Locale) -> String? {
        let remaining = reset.timeIntervalSince(now)
        guard remaining >= 60 else { return nil }
        let formatter = DateComponentsFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        formatter.calendar = calendar
        formatter.unitsStyle = .short
        formatter.maximumUnitCount = 2
        formatter.zeroFormattingBehavior = .dropAll
        formatter.allowedUnits = units(for: remaining)
        let text = formatter.string(from: remaining)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    private static func units(for interval: TimeInterval) -> NSCalendar.Unit {
        if interval >= 86_400 { return [.day, .hour] }
        if interval >= 3_600 { return [.hour, .minute] }
        return .minute
    }
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

    /// Legacy plans expose two monthly pools (Cursor models and third-party models).
    /// The X Subscription exposes one weekly included pool. Weekly usage resets on
    /// `includedUsageResetsAt`, which is not the monthly billing-cycle end.
    static func parseCursor(
        usage: [String: Any],
        plan: [String: Any]?,
        fetchedAt: Date = Date()
    ) -> AgentUsageSnapshot {
        let planInfo = dictionary(plan, "planInfo", "plan_info") ?? plan ?? [:]
        let period = cursorPeriod(planInfo["includedUsagePeriod"] ?? planInfo["included_usage_period"])
        let weeklyReset = parseResetDate(planInfo["includedUsageResetsAt"] ?? planInfo["included_usage_resets_at"])
        let cycleEnd = parseResetDate(
            planInfo["billingCycleEnd"]
                ?? planInfo["billing_cycle_end"]
                ?? usage["billingCycleEnd"]
                ?? usage["billing_cycle_end"]
        )
        let planUsage = dictionary(usage, "planUsage", "plan_usage") ?? [:]
        let reset = period == .weekly ? (weeklyReset ?? cycleEnd) : (cycleEnd ?? weeklyReset)
        let meters = cursorMeters(period: period, planUsage: planUsage, resetsAt: reset)
        return AgentUsageSnapshot(
            agent: .cursor,
            planName: stringValue(planInfo["planName"] ?? planInfo["plan_name"]),
            fiveHour: nil,
            sevenDay: nil,
            extra: nil,
            meters: meters,
            fetchedAt: fetchedAt,
            status: .ready
        )
    }

    /// Grok Build's `/usage` weekly pool. `creditUsagePercent` is already consumed.
    /// A missing percent is 0% only when the payload still describes a weekly period.
    static func parseGrokBuild(_ json: [String: Any], fetchedAt: Date = Date()) -> AgentUsageSnapshot {
        let config = dictionary(json, "config") ?? json
        let period = dictionary(config, "currentPeriod", "current_period")
        let reset = parseResetDate(period?["end"] ?? config["billingPeriodEnd"] ?? config["billing_period_end"])
        var used = coercePercent(config["creditUsagePercent"] ?? config["credit_usage_percent"])
        if used == nil {
            used = grokBuildProductPercent(config["productUsage"] ?? config["product_usage"])
        }
        if used == nil, isWeeklyGrokPeriod(period) {
            used = 0
        }
        return AgentUsageSnapshot(
            agent: .grok,
            planName: nil,
            fiveHour: nil,
            sevenDay: used.map { AgentUsageWindow(usedPercent: $0, resetsAt: reset) },
            extra: nil,
            fetchedAt: fetchedAt,
            status: .ready
        )
    }

    /// Grok Bot's weekly included pool from `GetSandUsageStatus`. `usagePercent` is already consumed.
    static func parseGrokBot(_ json: [String: Any], fetchedAt: Date = Date()) -> AgentUsageSnapshot {
        let allowanceFlag = json["hasNonZeroIncludedLimit"] ?? json["has_non_zero_included_limit"]
        let allowanceDenied = allowanceFlag != nil && !boolValue(allowanceFlag)
        let reported = coercePercent(json["usagePercent"] ?? json["usage_percent"])
        let reset = parseResetDate(json["nextResetTimestampUtc"] ?? json["next_reset_timestamp_utc"])
        let used: Double? = allowanceDenied ? nil : (reported ?? (reset == nil ? nil : 0))
        let plan = stringValue(json["grokPlanLabel"] ?? json["grok_plan_label"])
        return AgentUsageSnapshot(
            agent: .grokbot,
            planName: plan,
            fiveHour: nil,
            sevenDay: used.map { AgentUsageWindow(usedPercent: $0, resetsAt: reset) },
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
        if let shortened = shortenFractionalSeconds(raw), let date = fractional.date(from: shortened) {
            return date
        }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: raw)
    }

    /// Foundation accepts three fractional digits. Grok sends six.
    private static func shortenFractionalSeconds(_ raw: String) -> String? {
        guard let dot = raw.firstIndex(of: ".") else { return nil }
        let afterDot = raw.index(after: dot)
        let rest = raw[afterDot...]
        let digits = rest.prefix { $0.isNumber }
        guard digits.count > 3 else { return nil }
        let suffix = rest.dropFirst(digits.count)
        return String(raw[..<afterDot]) + String(digits.prefix(3)) + suffix
    }

    private enum CursorIncludedPeriod {
        case monthly
        case weekly
        case unspecified
    }

    private static func cursorMeters(
        period: CursorIncludedPeriod,
        planUsage: [String: Any],
        resetsAt: Date?
    ) -> [AgentUsageMeter] {
        if period == .weekly {
            guard let used = cursorIncludedUsedPercent(planUsage) else { return [] }
            return [AgentUsageMeter(label: "Week", window: AgentUsageWindow(usedPercent: used, resetsAt: resetsAt))]
        }

        let own = cursorPoolUsedPercent(
            spend: coerceDouble(planUsage["autoSpend"] ?? planUsage["auto_spend"]),
            limit: coerceDouble(planUsage["autoLimit"] ?? planUsage["auto_limit"]),
            reportedPercent: coerceDouble(planUsage["autoPercentUsed"] ?? planUsage["auto_percent_used"])
        )
        let external = cursorPoolUsedPercent(
            spend: coerceDouble(planUsage["apiSpend"] ?? planUsage["api_spend"]),
            limit: coerceDouble(planUsage["apiLimit"] ?? planUsage["api_limit"]),
            reportedPercent: coerceDouble(planUsage["apiPercentUsed"] ?? planUsage["api_percent_used"])
        )
        var meters: [AgentUsageMeter] = []
        if let own {
            meters.append(AgentUsageMeter(label: "Own models", window: AgentUsageWindow(usedPercent: own, resetsAt: resetsAt)))
        }
        if let external {
            meters.append(AgentUsageMeter(label: "External models", window: AgentUsageWindow(usedPercent: external, resetsAt: resetsAt)))
        }
        if meters.isEmpty, let used = cursorIncludedUsedPercent(planUsage) {
            let label = period == .monthly ? "Month" : "Included"
            meters.append(AgentUsageMeter(label: label, window: AgentUsageWindow(usedPercent: used, resetsAt: resetsAt)))
        }
        return meters
    }

    /// Prefer spend ÷ limit. Reported percents on this payload have disagreed with the allowance.
    private static func cursorPoolUsedPercent(spend: Double?, limit: Double?, reportedPercent: Double?) -> Double? {
        if let limit, limit > 0, let spend {
            return min(100, max(0, spend / limit * 100))
        }
        return coercePercent(reportedPercent)
    }

    private static func cursorIncludedUsedPercent(_ plan: [String: Any]) -> Double? {
        let limit = coerceDouble(plan["limit"])
        if let limit, limit > 0 {
            if let remaining = coerceDouble(plan["remaining"]) {
                return min(100, max(0, (limit - remaining) / limit * 100))
            }
            if let included = coerceDouble(plan["includedSpend"] ?? plan["included_spend"]) {
                return min(100, max(0, included / limit * 100))
            }
        }
        return coercePercent(plan["totalPercentUsed"] ?? plan["total_percent_used"])
    }

    private static func cursorPeriod(_ any: Any?) -> CursorIncludedPeriod {
        if let number = coerceDouble(any) {
            if number == 2 { return .weekly }
            if number == 1 { return .monthly }
            return .unspecified
        }
        guard let raw = (any as? String)?.lowercased() else { return .unspecified }
        if raw.contains("week") { return .weekly }
        if raw.contains("month") { return .monthly }
        return .unspecified
    }

    private static func grokBuildProductPercent(_ any: Any?) -> Double? {
        guard let products = any as? [Any] else { return nil }
        for item in products {
            guard let product = item as? [String: Any] else { continue }
            let name = (product["product"] as? String)?.lowercased() ?? ""
            guard name == "grokbuild" || name == "grok_build" else { continue }
            if let percent = coercePercent(product["usagePercent"] ?? product["usage_percent"]) {
                return percent
            }
        }
        return nil
    }

    private static func isWeeklyGrokPeriod(_ period: [String: Any]?) -> Bool {
        guard let period else { return false }
        let type = ((period["type"] as? String) ?? "").uppercased()
        guard type.contains("WEEKLY") else { return false }
        return parseResetDate(period["start"]) != nil && parseResetDate(period["end"]) != nil
    }

    private static func dictionary(_ json: [String: Any]?, _ keys: String...) -> [String: Any]? {
        guard let json else { return nil }
        for key in keys {
            if let value = json[key] as? [String: Any] { return value }
        }
        return nil
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
