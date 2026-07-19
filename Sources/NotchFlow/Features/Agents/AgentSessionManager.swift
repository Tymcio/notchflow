import AppKit
import Foundation

@MainActor
final class AgentSessionManager {
    var onStateChange: (() -> Void)?

    private(set) var sessions: [AgentSession] = []
    private var permissionDecisions: [String: AgentPermissionDecision] = [:]
    private var questionAnswers: [String: String] = [:]

    var primaryActivity: AgentSessionActivity? {
        // Prefer sessions that need attention, then most recently updated running session.
        let attention = sessions
            .filter { $0.phase == .waitingPermission || $0.phase == .waitingQuestion }
            .sorted { $0.updatedAt > $1.updatedAt }
        if let first = attention.first {
            return first.activity
        }
        return sessions
            .filter { $0.phase == .running || $0.phase == .done }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first?
            .activity
    }

    var attentionCount: Int {
        sessions.filter { $0.phase == .waitingPermission || $0.phase == .waitingQuestion }.count
    }

    func ingestEvent(_ payload: [String: Any]) {
        let sessionID = stringValue(payload["sessionId"] ?? payload["session_id"]) ?? UUID().uuidString
        let agent = AgentKind.from(raw: stringValue(payload["agent"]))
        let event = (stringValue(payload["event"]) ?? "update").lowercased()
        let title = stringValue(payload["title"]) ?? agent.displayName
        let detail = stringValue(payload["detail"])
            ?? stringValue(payload["message"])
            ?? stringValue(payload["toolName"])
            ?? ""
        let cwd = stringValue(payload["cwd"])
        let terminalBundleID = stringValue(payload["terminalBundleId"] ?? payload["terminal_bundle_id"])

        var session = sessions.first(where: { $0.id == sessionID }) ?? AgentSession(
            id: sessionID,
            agent: agent,
            title: title,
            detail: detail,
            phase: .running,
            cwd: cwd,
            terminalBundleID: terminalBundleID,
            updatedAt: Date(),
            permission: nil,
            question: nil
        )

        session.agent = agent
        if let titleValue = stringValue(payload["title"]), !titleValue.isEmpty {
            session.title = titleValue
        }
        if !detail.isEmpty {
            session.detail = detail
        }
        if let cwd { session.cwd = cwd }
        if let terminalBundleID { session.terminalBundleID = terminalBundleID }
        session.updatedAt = Date()

        switch event {
        case "session.started", "started", "start":
            session.phase = .running
            session.permission = nil
            session.question = nil
        case "tool", "tool.started", "progress":
            session.phase = .running
        case "permission", "permission.request":
            let permissionID = stringValue(payload["permissionId"] ?? payload["permission_id"]) ?? UUID().uuidString
            let toolName = stringValue(payload["toolName"] ?? payload["tool_name"]) ?? "Tool"
            let summary = stringValue(payload["summary"])
                ?? stringValue(payload["command"])
                ?? (detail.isEmpty ? toolName : detail)
            session.phase = .waitingPermission
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
            session.question = AgentQuestionRequest(
                id: questionID,
                prompt: prompt,
                options: options,
                createdAt: Date()
            )
        case "done", "session.done", "stop":
            session.phase = .done
            session.permission = nil
            session.question = nil
        case "error":
            session.phase = .error
        case "clear":
            removeSession(id: sessionID)
            return
        default:
            if session.phase != .waitingPermission && session.phase != .waitingQuestion {
                session.phase = .running
            }
        }

        upsert(session)
    }

    func decidePermission(id: String, decision: AgentPermissionDecision) {
        permissionDecisions[id] = decision
        if let index = sessions.firstIndex(where: { $0.permission?.id == id }) {
            sessions[index].permission = nil
            sessions[index].phase = decision == .allow ? .running : .error
            sessions[index].detail = decision == .allow ? loc("Approved") : loc("Denied")
            sessions[index].updatedAt = Date()
            onStateChange?()
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
        sessions.removeAll { $0.phase == .done || $0.phase == .error }
        onStateChange?()
    }

    func jump(to session: AgentSession) {
        let candidates = ([session.terminalBundleID].compactMap { $0 } + session.agent.preferredBundleIDs)
        for bundleID in candidates {
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            if let app = apps.first {
                app.activate()
                return
            }
        }
        // Fall back to opening Cursor / Terminal by bundle if installed.
        for bundleID in session.agent.preferredBundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                return
            }
        }
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
