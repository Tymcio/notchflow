import Foundation

@MainActor
@Observable
final class AgentUsageMonitor {
    private(set) var claude: AgentUsageSnapshot?
    private(set) var codex: AgentUsageSnapshot?
    private(set) var isRefreshing = false

    var onChange: (() -> Void)?

    private var pollTask: Task<Void, Never>?
    private var inFlight: Task<Void, Never>?
    private var isEnabled = false
    private var nextFetchAllowedAt: [AgentKind: Date] = [:]

    private let cacheTTL: TimeInterval = 5 * 60
    private let defaultBackoff: TimeInterval = 5 * 60

    var snapshots: [AgentUsageSnapshot] {
        [claude, codex].compactMap { $0 }
    }

    func idleHint(for agent: AgentKind) -> AgentUsageIdleHint? {
        switch agent {
        case .claude: AgentUsageParser.idleHint(from: claude)
        case .codex: AgentUsageParser.idleHint(from: codex)
        default: nil
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
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
    }

    private func refreshClaude(force: Bool) async {
        guard shouldFetch(.claude, current: claude, force: force, hasCredentials: AgentUsageClient.hasClaudeCredentials) else {
            if claude == nil, !AgentUsageClient.hasClaudeCredentials {
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
        guard shouldFetch(.codex, current: codex, force: force, hasCredentials: AgentUsageClient.hasCodexCredentials) else {
            if codex == nil, !AgentUsageClient.hasCodexCredentials {
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
