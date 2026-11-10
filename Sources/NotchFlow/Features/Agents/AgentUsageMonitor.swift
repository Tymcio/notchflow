import Foundation

@MainActor
@Observable
final class AgentUsageMonitor {
    private(set) var claude: AgentUsageSnapshot?
    private(set) var codex: AgentUsageSnapshot?
    private(set) var cursor: AgentUsageSnapshot?
    private(set) var grok: AgentUsageSnapshot?
    private(set) var grokBot: AgentUsageSnapshot?
    private(set) var isRefreshing = false

    var onChange: (() -> Void)?

    private var pollTask: Task<Void, Never>?
    private var inFlight: Task<Void, Never>?
    private var isEnabled = false
    /// Set by `showFixedSnapshots`: polling stays off and nothing is fetched again.
    private var isPinnedToFixedSnapshots = false
    private var nextFetchAllowedAt: [AgentKind: Date] = [:]

    private let cacheTTL: TimeInterval = 5 * 60
    private let defaultBackoff: TimeInterval = 5 * 60

    init(removesLegacyTokenCaches: Bool = true) {
        guard removesLegacyTokenCaches else { return }
        // Older builds kept refreshed Cursor / Grok Bot tokens in plain-text files.
        Task.detached(priority: .utility) {
            AgentUsageClient.removeLegacyTokenCaches()
        }
    }

    var snapshots: [AgentUsageSnapshot] {
        [claude, codex, cursor, grok, grokBot].compactMap { $0 }
    }

    func idleHint(for agent: AgentKind) -> AgentUsageIdleHint? {
        switch agent {
        case .claude: AgentUsageParser.idleHint(from: claude)
        case .codex: AgentUsageParser.idleHint(from: codex)
        case .cursor: AgentUsageParser.idleHint(from: cursor)
        case .grok: AgentUsageParser.idleHint(from: grok)
        case .grokbot: AgentUsageParser.idleHint(from: grokBot)
        default: nil
        }
    }

    /// Shows these snapshots instead of fetched ones (debug demo mode). Polling stops for
    /// good: no credentials, files, Keychain items or network are touched afterwards.
    func showFixedSnapshots(_ fixed: [AgentUsageSnapshot]) {
        setEnabled(false)
        isPinnedToFixedSnapshots = true
        claude = fixed.first { $0.agent == .claude }
        codex = fixed.first { $0.agent == .codex }
        cursor = fixed.first { $0.agent == .cursor }
        grok = fixed.first { $0.agent == .grok }
        grokBot = fixed.first { $0.agent == .grokbot }
        onChange?()
    }

    func setEnabled(_ enabled: Bool) {
        guard !isPinnedToFixedSnapshots, isEnabled != enabled else { return }
        isEnabled = enabled
        if enabled {
            startPolling()
            Task { await refresh(force: false) }
        } else {
            stopPolling()
        }
    }

    func refresh(force: Bool) async {
        guard isEnabled else { return }
        if let inFlight {
            await inFlight.value
            guard force else { return }
        }
        let task = Task { await self.refreshProviders(force: force) }
        inFlight = task
        await task.value
        inFlight = nil
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5 * 60))
                guard !Task.isCancelled else { return }
                await self?.refresh(force: false)
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        inFlight?.cancel()
        inFlight = nil
    }

    private func refreshProviders(force: Bool) async {
        isRefreshing = true
        defer {
            isRefreshing = false
            onChange?()
        }
        await refreshClaude(force: force)
        await refreshCodex(force: force)
        await refreshCursor(force: force)
        await refreshGrokBuild(force: force)
        await refreshGrokBot(force: force)
    }

    private func refreshClaude(force: Bool) async {
        if !force, !isFetchDue(.claude, current: claude) {
            return
        }
        let hasCredentials = await Self.offMain { AgentUsageClient.hasClaudeCredentials }
        guard hasCredentials else {
            if claude == nil {
                claude = statusSnapshot(agent: .claude, status: .signedOut)
            }
            return
        }
        do {
            claude = try await AgentUsageClient.fetchClaude(allowKeychainPrompt: force)
            nextFetchAllowedAt[.claude] = Date().addingTimeInterval(cacheTTL)
        } catch let error as AgentUsageClient.FetchError {
            apply(error, to: .claude, current: &claude)
        } catch {
            apply(.http(-1), to: .claude, current: &claude)
        }
    }

    private func refreshCodex(force: Bool) async {
        let hasCredentials = await Self.offMain { AgentUsageClient.hasCodexCredentials }
        guard shouldFetch(.codex, current: codex, force: force, hasCredentials: hasCredentials) else {
            if codex == nil, !hasCredentials {
                codex = statusSnapshot(agent: .codex, status: .signedOut)
            }
            return
        }
        do {
            codex = try await AgentUsageClient.fetchCodex()
            nextFetchAllowedAt[.codex] = Date().addingTimeInterval(cacheTTL)
        } catch let error as AgentUsageClient.FetchError {
            apply(error, to: .codex, current: &codex)
        } catch {
            apply(.http(-1), to: .codex, current: &codex)
        }
    }

    private func refreshCursor(force: Bool) async {
        let hasCredentials = await Self.offMain { AgentUsageClient.hasCursorCredentials }
        guard shouldFetch(.cursor, current: cursor, force: force, hasCredentials: hasCredentials) else {
            if cursor == nil, !hasCredentials {
                cursor = statusSnapshot(agent: .cursor, status: .signedOut)
            }
            return
        }
        do {
            cursor = try await AgentUsageClient.fetchCursor(allowKeychainPrompt: force)
            nextFetchAllowedAt[.cursor] = Date().addingTimeInterval(cacheTTL)
        } catch let error as AgentUsageClient.FetchError {
            apply(error, to: .cursor, current: &cursor)
        } catch {
            apply(.http(-1), to: .cursor, current: &cursor)
        }
    }

    private func refreshGrokBuild(force: Bool) async {
        let hasCredentials = await Self.offMain { AgentUsageClient.hasGrokBuildCredentials }
        guard shouldFetch(.grok, current: grok, force: force, hasCredentials: hasCredentials) else {
            if grok == nil, !hasCredentials {
                grok = statusSnapshot(agent: .grok, status: .signedOut)
            }
            return
        }
        do {
            grok = try await AgentUsageClient.fetchGrokBuild()
            nextFetchAllowedAt[.grok] = Date().addingTimeInterval(cacheTTL)
        } catch let error as AgentUsageClient.FetchError {
            apply(error, to: .grok, current: &grok)
        } catch {
            apply(.http(-1), to: .grok, current: &grok)
        }
    }

    private func refreshGrokBot(force: Bool) async {
        let hasCredentials = await Self.offMain { AgentUsageClient.hasGrokBotCredentials }
        guard shouldFetch(.grokbot, current: grokBot, force: force, hasCredentials: hasCredentials) else {
            if grokBot == nil, !hasCredentials {
                grokBot = statusSnapshot(agent: .grokbot, status: .signedOut)
            }
            return
        }
        do {
            grokBot = try await AgentUsageClient.fetchGrokBot(allowKeychainPrompt: force)
            nextFetchAllowedAt[.grokbot] = Date().addingTimeInterval(cacheTTL)
        } catch let error as AgentUsageClient.FetchError {
            apply(error, to: .grokbot, current: &grokBot)
        } catch {
            apply(.http(-1), to: .grokbot, current: &grokBot)
        }
    }

    /// Credential checks read files, Cursor's SQLite database (with a busy timeout) and
    /// the Keychain. Run them off the main thread so the island never stalls on them.
    private nonisolated static func offMain(_ check: @escaping @Sendable () -> Bool) async -> Bool {
        await Task.detached(priority: .utility) { check() }.value
    }

    /// False while a recent result or backoff is still in force. Checked before
    /// any credential lookup so a Claude session tick cannot touch Keychain.
    private func isFetchDue(_ agent: AgentKind, current: AgentUsageSnapshot?) -> Bool {
        if let until = nextFetchAllowedAt[agent], until > Date() {
            return false
        }
        if let current, current.hasMeters, Date().timeIntervalSince(current.fetchedAt) < cacheTTL {
            return false
        }
        return true
    }

    private func shouldFetch(
        _ agent: AgentKind,
        current: AgentUsageSnapshot?,
        force: Bool,
        hasCredentials: Bool
    ) -> Bool {
        guard hasCredentials else { return false }
        if force { return true }
        if let until = nextFetchAllowedAt[agent], until > Date() {
            return false
        }
        if let current, current.hasMeters, Date().timeIntervalSince(current.fetchedAt) < cacheTTL {
            return false
        }
        return true
    }

    private func apply(
        _ error: AgentUsageClient.FetchError,
        to agent: AgentKind,
        current: inout AgentUsageSnapshot?
    ) {
        switch error {
        case .signedOut:
            current = statusSnapshot(agent: agent, status: .signedOut)
            nextFetchAllowedAt[agent] = Date().addingTimeInterval(cacheTTL)
        case .needsKeychainAccess:
            current = statusSnapshot(agent: agent, status: .needsKeychainAccess)
            nextFetchAllowedAt[agent] = Date().addingTimeInterval(30)
        case .loginExpired:
            current = statusSnapshot(agent: agent, status: .loginExpired)
            nextFetchAllowedAt[agent] = Date().addingTimeInterval(cacheTTL)
        case .rateLimited(let retryAfter):
            if var existing = current, existing.hasMeters {
                existing.status = .rateLimited
                current = existing
            } else {
                current = AgentUsageSnapshot(
                    agent: agent,
                    planName: nil,
                    fiveHour: nil,
                    sevenDay: nil,
                    extra: nil,
                    fetchedAt: Date(),
                    status: .rateLimited
                )
            }
            nextFetchAllowedAt[agent] = Date().addingTimeInterval(retryAfter ?? defaultBackoff)
        case .http, .invalidResponse:
            if current?.hasMeters == true {
                nextFetchAllowedAt[agent] = Date().addingTimeInterval(60)
                return
            }
            current = AgentUsageSnapshot(
                agent: agent,
                planName: nil,
                fiveHour: nil,
                sevenDay: nil,
                extra: nil,
                fetchedAt: Date(),
                status: .unavailable
            )
            nextFetchAllowedAt[agent] = Date().addingTimeInterval(cacheTTL)
        }
    }

    private func statusSnapshot(agent: AgentKind, status: AgentUsageStatus) -> AgentUsageSnapshot {
        AgentUsageSnapshot(
            agent: agent,
            planName: nil,
            fiveHour: nil,
            sevenDay: nil,
            extra: nil,
            fetchedAt: Date(),
            status: status
        )
    }
}
