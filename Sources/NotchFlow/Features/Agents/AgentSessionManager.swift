import AppKit
import Foundation

@MainActor
final class AgentSessionManager {
    var onStateChange: (() -> Void)?
    /// Fired when a session newly needs the user (notch approval or jump-to-agent).
    var onNeedsAttention: ((AgentSession) -> Void)?

    private(set) var sessions: [AgentSession] = []
    private var permissionDecisions: [String: AgentPermissionDecision] = [:]
    private var questionAnswers: [String: String] = [:]
    private var finishClearTasks: [String: Task<Void, Never>] = [:]
    private var staleWatchdogTask: Task<Void, Never>?
    private var lastAutoJumpSessionID: String?

    /// After this quiet period, a "running" session is treated as finished.
    /// Covers Cursor `stop` payloads that omit conversation_id.
    private let staleRunningInterval: TimeInterval = 20
    /// Placeholder "Working…" rows (after jump-only attention) go away faster.
    private let stalePlaceholderInterval: TimeInterval = 8

    init() {
        startStaleWatchdog()
    }

    deinit {
        staleWatchdogTask?.cancel()
    }

    /// Idle wing: attention first, then active work. Finished sessions never stay on the notch.
    var primaryActivity: AgentSessionActivity? {
        let attention = sessions
            .filter { $0.phase == .waitingPermission || $0.phase == .waitingQuestion }
            .sorted { $0.updatedAt > $1.updatedAt }
        if let first = attention.first {
            return first.activity
        }
        return sessions
            .filter { $0.phase == .running }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first?
            .activity
    }

    var attentionCount: Int {
        sessions.filter { $0.phase == .waitingPermission || $0.phase == .waitingQuestion }.count
    }

    func ingestEvent(_ payload: [String: Any]) {
        let agent = AgentKind.from(raw: stringValue(payload["agent"]))
        let event = (stringValue(payload["event"]) ?? "update").lowercased()
        let detail = stringValue(payload["detail"])
            ?? stringValue(payload["message"])
            ?? stringValue(payload["summary"])
            ?? stringValue(payload["toolName"] ?? payload["tool_name"])
            ?? ""
        let cwd = stringValue(payload["cwd"])
        let terminalBundleID = stringValue(payload["terminalBundleId"] ?? payload["terminal_bundle_id"])
        let finishAll = boolValue(payload["finishAll"])
        var sessionID = stringValue(payload["sessionId"] ?? payload["session_id"]) ?? ""

        switch event {
        case "done", "session.done", "stop":
            finishSessions(
                agent: agent,
                sessionID: sessionID,
                finishAll: finishAll || sessionID.isEmpty,
                detail: detail.isEmpty ? loc("Done") : detail
            )
            return
        case "error":
            finishSessions(
                agent: agent,
                sessionID: sessionID,
                finishAll: finishAll || sessionID.isEmpty,
                detail: detail.isEmpty ? loc("Error") : detail,
                asError: true
            )
            return
        case "clear":
            if sessionID.isEmpty {
                clearFinished()
            } else {
                removeSession(id: sessionID)
            }
            return
        default:
            break
        }

        if sessionID.isEmpty {
            sessionID = UUID().uuidString
        }

        cancelFinishClear(for: sessionID)

        let previousNeedsAttention = sessions.first(where: { $0.id == sessionID })?.needsAttention ?? false

        var session = sessions.first(where: { $0.id == sessionID }) ?? AgentSession(
            id: sessionID,
            agent: agent,
            title: agent.displayName,
            detail: detail,
            phase: .running,
            cwd: cwd,
            terminalBundleID: terminalBundleID,
            updatedAt: Date(),
            permission: nil,
            question: nil
        )

        session.agent = agent
        // Headline stays the agent name; tool/path live in detail (avoids idle "Write").
        session.title = agent.displayName
        if !detail.isEmpty {
            session.detail = detail
        }
        if let cwd { session.cwd = cwd }
        if let terminalBundleID { session.terminalBundleID = terminalBundleID }
        session.updatedAt = Date()

        switch event {
        case "session.started", "started", "start":
            // New composer/turn: close older running rows for this agent without a matching id.
            finishOtherRunningSessions(of: agent, except: sessionID)
            session.phase = .running
            session.permission = nil
            session.question = nil
            if session.detail.isEmpty {
                session.detail = loc("Working…")
            }
        case "tool", "tool.started", "progress":
            session.phase = .running
            session.permission = nil
            session.question = nil
        case "attention", "needs.input", "needs_input":
            // Cursor-style: consent stays in the agent UI — notch pulses and we jump.
            session.phase = .waitingPermission
            session.permission = nil
            session.question = nil
            if session.detail.isEmpty {
                session.detail = loc("Needs approval")
            }
        case "permission", "permission.request":
            // Real consent prompts only (e.g. Claude PermissionRequest).
            let permissionID = stringValue(payload["permissionId"] ?? payload["permission_id"]) ?? UUID().uuidString
            let toolName = stringValue(payload["toolName"] ?? payload["tool_name"]) ?? "Tool"
            let summary = stringValue(payload["summary"])
                ?? stringValue(payload["command"])
                ?? (detail.isEmpty ? toolName : detail)
            session.phase = .waitingPermission
            session.detail = summary
            session.permission = AgentPermissionRequest(
                id: permissionID,
                toolName: toolName,
                summary: summary,
                createdAt: Date()
            )
            permissionDecisions.removeValue(forKey: permissionID)
        case "question", "ask":
            let questionID = stringValue(payload["questionId"] ?? payload["question_id"]) ?? UUID().uuidString
            let prompt = stringValue(payload["prompt"]) ?? detail
            let options = parseOptions(payload["options"])
            session.phase = .waitingQuestion
            session.detail = prompt
            session.question = AgentQuestionRequest(
                id: questionID,
                prompt: prompt,
                options: options,
                createdAt: Date()
            )
        default:
            if session.phase != .waitingPermission && session.phase != .waitingQuestion {
                session.phase = .running
            }
        }

        upsert(session)
        if session.needsAttention {
            if !previousNeedsAttention {
                onNeedsAttention?(session)
            }
        } else if lastAutoJumpSessionID == session.id {
            lastAutoJumpSessionID = nil
        }
    }

    func decidePermission(id: String, decision: AgentPermissionDecision) {
        permissionDecisions[id] = decision
        if let index = sessions.firstIndex(where: { $0.permission?.id == id }) {
            sessions[index].permission = nil
            sessions[index].phase = decision == .allow ? .running : .error
            sessions[index].detail = decision == .allow ? loc("Approved") : loc("Denied")
            sessions[index].updatedAt = Date()
            onStateChange?()
            if decision == .deny {
                scheduleFinishClear(id: sessions[index].id)
            }
        }
    }

    func permissionDecision(id: String) -> AgentPermissionDecision? {
        permissionDecisions[id]
    }

    func answerQuestion(id: String, optionID: String) {
        questionAnswers[id] = optionID
        if let index = sessions.firstIndex(where: { $0.question?.id == id }) {
            let label = sessions[index].question?.options.first(where: { $0.id == optionID })?.label
            sessions[index].question = nil
            sessions[index].phase = .running
            sessions[index].detail = label.map { loc("Answered: \($0)") } ?? loc("Answered")
            sessions[index].updatedAt = Date()
            onStateChange?()
        }
    }

    func questionAnswer(id: String) -> String? {
        questionAnswers[id]
    }

    func clearSession(id: String) {
        removeSession(id: id)
    }

    func clearFinished() {
        for session in sessions where session.phase == .done || session.phase == .error {
            cancelFinishClear(for: session.id)
        }
        sessions.removeAll { $0.phase == .done || $0.phase == .error }
        onStateChange?()
    }

    func jump(to session: AgentSession) {
        // Prefer bringing an already-running agent/IDE forward.
        let candidates = ([session.terminalBundleID].compactMap { $0 } + session.agent.preferredBundleIDs)
        var didActivate = false
        for bundleID in candidates {
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            if let app = apps.first {
                app.activate()
                didActivate = true
                break
            }
        }
        if !didActivate {
            // Cursor: reopen workspace when we know the cwd.
            if session.agent == .cursor, let cwd = session.cwd, !cwd.isEmpty {
                let url = URL(fileURLWithPath: cwd, isDirectory: true)
                let config = NSWorkspace.OpenConfiguration()
                if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.todesktop.230313mzl4w4u92")
                    ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.cursorapp.Cursor") {
                    NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config)
                    didActivate = true
                }
            }
        }
        if !didActivate {
            // Fall back to opening Cursor / Terminal by bundle if installed.
            for bundleID in session.agent.preferredBundleIDs {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                    break
                }
            }
        }
        // After jump, jump-only attention is informational — clear soon so it doesn't stick.
        if session.needsAttention, !session.showsNotchApproval {
            scheduleJumpOnlyAttentionClear(id: session.id)
        }
    }

    /// Jump only when the agent app is not already frontmost (avoids focus thrash).
    func jumpIfNeeded(for session: AgentSession) {
        if lastAutoJumpSessionID == session.id, session.needsAttention {
            return
        }
        let frontID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let targets = Set(([session.terminalBundleID].compactMap { $0 } + session.agent.preferredBundleIDs))
        if let frontID, targets.contains(frontID) {
            // Already in Cursor — still soften jump-only attention so it doesn't stick forever.
            if !session.showsNotchApproval {
                scheduleJumpOnlyAttentionClear(id: session.id)
            }
            return
        }
        lastAutoJumpSessionID = session.id
        jump(to: session)
    }

    /// Jump-only Cursor prompts: after jump, dismiss the row — don't leave a fake "Working…".
    /// Real follow-up tool/stop events will create a fresh running session if needed.
    private func scheduleJumpOnlyAttentionClear(id: String) {
        cancelFinishClear(for: id)
        finishClearTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      let index = self.sessions.firstIndex(where: { $0.id == id }) else { return }
                let session = self.sessions[index]
                guard session.phase == .waitingPermission,
                      session.permission == nil,
                      session.question == nil else { return }
                if self.lastAutoJumpSessionID == id {
                    self.lastAutoJumpSessionID = nil
                }
                self.finishClearTasks[id] = nil
                self.finishSessions(
                    agent: session.agent,
                    sessionID: session.id,
                    finishAll: false,
                    detail: loc("Done")
                )
            }
        }
    }

    private func finishSessions(
        agent: AgentKind,
        sessionID: String,
        finishAll: Bool,
        detail: String,
        asError: Bool = false
    ) {
        let phase: AgentSessionPhase = asError ? .error : .done
        var ids: [String] = []

        if !sessionID.isEmpty, sessions.contains(where: { $0.id == sessionID }) {
            ids = [sessionID]
        } else if finishAll {
            ids = sessions
                .filter { $0.agent == agent && ($0.phase == .running || $0.phase == .waitingPermission || $0.phase == .waitingQuestion) }
                .map(\.id)
        } else if let newest = sessions
            .filter({ $0.agent == agent && $0.phase == .running })
            .sorted(by: { $0.updatedAt > $1.updatedAt })
            .first {
            ids = [newest.id]
        } else if !sessionID.isEmpty {
            ids = [sessionID]
        }

        guard !ids.isEmpty else { return }

        for id in ids {
            cancelFinishClear(for: id)
            if let index = sessions.firstIndex(where: { $0.id == id }) {
                sessions[index].phase = phase
                sessions[index].detail = detail
                sessions[index].permission = nil
                sessions[index].question = nil
                sessions[index].updatedAt = Date()
                scheduleFinishClear(id: id)
            } else {
                let session = AgentSession(
                    id: id,
                    agent: agent,
                    title: agent.displayName,
                    detail: detail,
                    phase: phase,
                    cwd: nil,
                    terminalBundleID: nil,
                    updatedAt: Date(),
                    permission: nil,
                    question: nil
                )
                sessions.insert(session, at: 0)
                scheduleFinishClear(id: id)
            }
        }
        onStateChange?()
    }

    private func finishOtherRunningSessions(of agent: AgentKind, except sessionID: String) {
        let staleIDs = sessions
            .filter { $0.agent == agent && $0.id != sessionID && $0.phase == .running }
            .map(\.id)
        for id in staleIDs {
            finishSessions(agent: agent, sessionID: id, finishAll: false, detail: loc("Done"))
        }
    }

    private func startStaleWatchdog() {
        staleWatchdogTask?.cancel()
        staleWatchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.finishStaleRunningSessions()
                }
            }
        }
    }

    private func finishStaleRunningSessions() {
        let now = Date()
        let runningCutoff = now.addingTimeInterval(-staleRunningInterval)
        let placeholderCutoff = now.addingTimeInterval(-stalePlaceholderInterval)
        let placeholderDetails = Set([loc("Working…"), "Working…", "Pracuje…"])

        let stale = sessions.filter { session in
            if session.phase == .waitingPermission,
               session.permission == nil,
               session.question == nil,
               session.updatedAt < placeholderCutoff {
                return true
            }
            guard session.phase == .running else { return false }
            if placeholderDetails.contains(session.detail), session.updatedAt < placeholderCutoff {
                return true
            }
            return session.updatedAt < runningCutoff
        }
        for session in stale {
            finishSessions(
                agent: session.agent,
                sessionID: session.id,
                finishAll: false,
                detail: loc("Done")
            )
        }
    }

    private func scheduleFinishClear(id: String) {
        cancelFinishClear(for: id)
        finishClearTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self?.removeSession(id: id)
            self?.finishClearTasks[id] = nil
        }
    }

    private func cancelFinishClear(for id: String) {
        finishClearTasks[id]?.cancel()
        finishClearTasks[id] = nil
    }

    private func upsert(_ session: AgentSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.insert(session, at: 0)
        }
        // Keep a reasonable history.
        if sessions.count > 20 {
            sessions = Array(sessions.prefix(20))
        }
        onStateChange?()
    }

    private func removeSession(id: String) {
        cancelFinishClear(for: id)
        sessions.removeAll { $0.id == id }
        onStateChange?()
    }

    private func stringValue(_ any: Any?) -> String? {
        if let string = any as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = any as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private func boolValue(_ any: Any?) -> Bool {
        if let bool = any as? Bool { return bool }
        if let number = any as? NSNumber { return number.boolValue }
        if let string = any as? String {
            return ["1", "true", "yes"].contains(string.lowercased())
        }
        return false
    }

    private func parseOptions(_ any: Any?) -> [AgentQuestionOption] {
        guard let array = any as? [Any] else { return [] }
        return array.enumerated().compactMap { index, item in
            if let string = item as? String {
                return AgentQuestionOption(id: "\(index)", label: string)
            }
            if let dict = item as? [String: Any],
               let label = stringValue(dict["label"] ?? dict["title"] ?? dict["text"]) {
                let id = stringValue(dict["id"]) ?? "\(index)"
                return AgentQuestionOption(id: id, label: label)
            }
            return nil
        }
    }
}
