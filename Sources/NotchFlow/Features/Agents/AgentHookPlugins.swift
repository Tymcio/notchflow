import Foundation

/// Text-based integrations: the OpenCode / Kilo Code plugin file and the Crush `crushrc` block.
extension AgentHooksInstaller {
    /// First line of every plugin file NotchFlow writes. Files without it are never touched.
    static let pluginHeader = "// Installed by NotchFlow"

    static let crushBlockStart = "# >>> NotchFlow agent hooks (managed by NotchFlow, removed by Disconnect) >>>"
    static let crushBlockEnd = "# <<< NotchFlow agent hooks <<<"

    // MARK: - OpenCode and Kilo Code

    static func installPlugin(at url: URL, agent: AgentKind, scriptPath: String) throws {
        let source = pluginSource(agent: agent, scriptPath: scriptPath)
        try ExternalConfigFile.updateText(at: url) { existing in
            if let existing, !existing.hasPrefix(pluginHeader) {
                throw ExternalConfigError.notOwnedByNotchFlow(path: url.path)
            }
            return source
        }
    }

    /// An ES module that works as an OpenCode V1 plugin (`server`), an OpenCode V2 plugin
    /// (`setup`) and a Kilo Code plugin (`server`). It runs the hook script fire-and-forget for a
    /// few events and never throws into the agent.
    static func pluginSource(agent: AgentKind, scriptPath: String) -> String {
        let pathLiteral = jsStringLiteral(scriptPath)
        return """
        \(pluginHeader). Shows \(agent.displayName) activity in the NotchFlow notch on this Mac.
        // NotchFlow rewrites or removes this file from Settings > Integrations > Agents. Safe to delete.
        import { spawn } from "node:child_process"

        const HOOK = \(pathLiteral)
        const AGENT = "\(agent.rawValue)"
        const busy = new Set()

        function text(value) {
          return typeof value === "string" ? value : ""
        }

        function send(event, payload) {
          try {
            const child = spawn(HOOK, [], {
              env: { ...process.env, NOTCHFLOW_AGENT: AGENT, NOTCHFLOW_HOOK_EVENT: event },
              stdio: ["pipe", "ignore", "ignore"],
              detached: true,
            })
            child.on("error", () => {})
            child.stdin.on("error", () => {})
            child.stdin.end(JSON.stringify(payload))
            child.unref()
          } catch {}
        }

        function started(sessionID, cwd) {
          if (busy.has(sessionID)) return
          busy.add(sessionID)
          send("session.busy", { session_id: sessionID, cwd })
        }

        function finished(sessionID, cwd) {
          if (!busy.delete(sessionID)) return
          send("session.idle", { session_id: sessionID, cwd })
        }

        function failed(sessionID, cwd, error) {
          busy.delete(sessionID)
          const e = error || {}
          const message = text(e.message) || text(e.data && e.data.message) || text(e.name)
          send("session.error", { session_id: sessionID, cwd, message })
        }

        function asked(p, cwd) {
          const patterns = Array.isArray(p.patterns) ? p.patterns.join(" ") : text(p.pattern)
          send("permission.asked", {
            session_id: text(p.sessionID),
            cwd,
            tool_name: text(p.permission) || text(p.type),
            message: text(p.title) || patterns,
          })
        }

        function onEvent(event, cwd) {
          try {
            if (!event || typeof event.type !== "string") return
            const p = event.properties || event.data || {}
            const sessionID = text(p.sessionID)
            switch (event.type) {
              case "session.status": {
                const kind = p.status && p.status.type
                if (kind === "busy") started(sessionID, cwd)
                else if (kind === "idle") finished(sessionID, cwd)
                break
              }
              case "session.idle":
                finished(sessionID, cwd)
                break
              case "session.error":
              case "session.execution.failed":
                failed(sessionID, cwd, p.error)
                break
              case "permission.asked":
              case "permission.updated":
                asked(p, cwd)
                break
              case "permission.replied":
                send("permission.replied", { session_id: sessionID, cwd })
                break
            }
          } catch {}
        }

        function toolStarted(sessionID, tool, args, cwd) {
          try {
            if (!text(tool)) return
            send("tool.execute.before", {
              session_id: text(sessionID),
              cwd,
              tool_name: text(tool),
              tool_input: args && typeof args === "object" ? args : {},
            })
          } catch {}
        }

        // OpenCode V1 and Kilo Code.
        async function server(input) {
          const cwd = text(input && (input.directory || input.worktree))
          return {
            event: async (arg) => onEvent(arg && arg.event, cwd),
            "tool.execute.before": async (input, output) =>
              toolStarted(input && input.sessionID, input && input.tool, output && output.args, cwd),
          }
        }

        // OpenCode V2.
        async function setup(ctx) {
          const controller = new AbortController()
          try {
            const cwd = text(ctx && ctx.location && ctx.location.directory)
            void (async () => {
              try {
                for await (const event of ctx.event.subscribe({ signal: controller.signal })) onEvent(event, cwd)
              } catch {}
            })()
            await ctx.tool.hook("execute.before", (event) => {
              toolStarted(event && event.sessionID, event && event.tool, event && event.input, cwd)
            })
          } catch {}
          return () => controller.abort()
        }

        export default { id: "notchflow", setup, server }

        """
    }

    private static func jsStringLiteral(_ value: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [value], options: [.withoutEscapingSlashes])) ?? Data()
        let array = String(data: data, encoding: .utf8) ?? "[\"\"]"
        // `["…"]` → `"…"`; JSON string syntax is valid JavaScript.
        return String(array.dropFirst().dropLast())
    }

    // MARK: - Crush

    /// Crush events NotchFlow listens to. Monitor only: hooks print nothing, so Crush decides.
    static let crushEvents = [
        "SessionStart", "TurnStart", "PreToolUse", "PermissionRequest", "PermissionResult", "TurnEnd", "StopFailure",
    ]

    static func crushBlock(scriptPath: String) -> String {
        var lines = [crushBlockStart]
        for event in crushEvents {
            let command = envCommand(agent: .crush, event: event, scriptPath: scriptPath)
            lines.append("hook add \(event) --name notchflow --timeout 10 --command \(shellQuote(command))")
        }
        lines.append(crushBlockEnd)
        return lines.joined(separator: "\n") + "\n"
    }

    /// `text` (nil for a missing crushrc) with NotchFlow's block replaced by a fresh one at the end.
    static func crushConfig(replacing text: String?, scriptPath: String) -> String {
        var body = removingCrushBlock(from: text ?? "")
        if !body.isEmpty {
            if !body.hasSuffix("\n") { body += "\n" }
            body += "\n"
        }
        return body + crushBlock(scriptPath: scriptPath)
    }

    /// `text` without NotchFlow's block (and the blank line NotchFlow put before it).
    static func removingCrushBlock(from text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        guard let start = lines.firstIndex(of: crushBlockStart) else { return text }
        let end = lines[start...].firstIndex(of: crushBlockEnd) ?? (lines.count - 1)
        var removeFrom = start
        if removeFrom > 0, lines[removeFrom - 1].isEmpty { removeFrom -= 1 }
        var removeTo = end
        // The block ends with a newline: drop the empty element after it too when it is last.
        if removeTo + 1 == lines.count - 1, lines[removeTo + 1].isEmpty { removeTo += 1 }
        lines.removeSubrange(removeFrom...removeTo)
        var result = lines.joined(separator: "\n")
        if !result.isEmpty, !result.hasSuffix("\n") { result += "\n" }
        return result
    }
}
