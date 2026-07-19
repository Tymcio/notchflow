import Foundation

enum AgentSessionPhase: String, Codable, Sendable {
    case running
    case waitingPermission
    case waitingQuestion
    case done
    case error
}

struct AgentPermissionRequest: Equatable, Identifiable, Sendable {
    let id: String
    let toolName: String
    let summary: String
    let createdAt: Date
}

struct AgentQuestionOption: Equatable, Identifiable, Sendable {
    let id: String
    let label: String
}

struct AgentQuestionRequest: Equatable, Identifiable, Sendable {
    let id: String
    let prompt: String
    let options: [AgentQuestionOption]
    let createdAt: Date
}

struct AgentSession: Equatable, Identifiable, Sendable {
    let id: String
    var agent: AgentKind
    var title: String
    var detail: String
    var phase: AgentSessionPhase
    var cwd: String?
    var terminalBundleID: String?
    var updatedAt: Date
    var permission: AgentPermissionRequest?
    var question: AgentQuestionRequest?

    var activity: AgentSessionActivity {
        AgentSessionActivity(
            id: id,
            agent: agent,
            title: title,
            detail: detail,
            phase: phase,
            updatedAt: updatedAt,
            needsAttention: phase == .waitingPermission || phase == .waitingQuestion
        )
    }
}

struct AgentSessionActivity: Equatable, Sendable {
    let id: String
    let agent: AgentKind
    let title: String
    let detail: String
    let phase: AgentSessionPhase
    let updatedAt: Date
    let needsAttention: Bool
}

enum AgentPermissionDecision: String, Codable, Sendable {
    case allow
    case deny
}
