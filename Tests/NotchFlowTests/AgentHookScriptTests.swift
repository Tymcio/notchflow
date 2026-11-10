import XCTest
@testable import NotchFlow

/// Runs the bundled hook script with a fake HOME and each agent's documented sample payload.
final class AgentHookScriptTests: XCTestCase {
    private var root: URL!
    private var home: URL!
    private var server: Process?

    private static let scriptURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/NotchFlow/Resources/AgentHooks/notchflow-agent-hook.sh")

    private var supportFolder: URL { home.appendingPathComponent("Library/Application Support/NotchFlow") }
    private var postLog: URL { root.appendingPathComponent("posts.log") }

    override func setUpWithError() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/python3") else {
            throw XCTSkip("python3 is missing")
        }
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nf-hook-\(UUID().uuidString)", isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: supportFolder, withIntermediateDirectories: true)
        try "test-token".write(to: supportFolder.appendingPathComponent("api-token"), atomically: true, encoding: .utf8)
        // Port 1: nothing listens there, so every request fails fast.
        try writePort(1)
    }

    override func tearDownWithError() throws {
        server?.terminate()
        server?.waitUntilExit()
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    // MARK: - Helpers

    private func writePort(_ port: Int) throws {
        try #"{"port": \#(port)}"#.write(to: supportFolder.appendingPathComponent("api.json"), atomically: true, encoding: .utf8)
    }

    private struct Run {
        let status: Int32
        let stdout: String
    }

    private func runHook(agent: String, event: String, payload: String) throws -> Run {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [Self.scriptURL.path]
        process.environment = [
            "HOME": home.path,
            "PATH": "/usr/bin:/bin",
            "NOTCHFLOW_AGENT": agent,
            "NOTCHFLOW_HOOK_EVENT": event,
        ]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        input.fileHandleForWriting.write(Data(payload.utf8))
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Run(status: process.terminationStatus, stdout: String(decoding: data, as: UTF8.self))
    }

    /// Runs the samples in parallel (each run starts several python3 processes).
    private func runAll(_ samples: [(String, String, String)]) -> [Run?] {
        var results = [Run?](repeating: nil, count: samples.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: samples.count) { index in
            let (agent, event, payload) = samples[index]
            let run = try? runHook(agent: agent, event: event, payload: payload)
            lock.lock()
            results[index] = run
            lock.unlock()
        }
        return results
    }

    /// A tiny local NotchFlow stand-in: POST /v1/agents/events → {"ok":true} (logged),
    /// GET /v1/agents/permission/<id> → {"decision": <decision>}.
    private func startServer(decision: String) throws {
        let serverScript = root.appendingPathComponent("server.py")
        try """
        import http.server, json, sys

        class Handler(http.server.BaseHTTPRequestHandler):
            def reply(self, body):
                data = json.dumps(body).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def do_POST(self):
                body = self.rfile.read(int(self.headers.get("Content-Length") or 0))
                if self.path == "/v1/agents/events":
                    with open(sys.argv[3], "ab") as log:
                        log.write(body + b"\\n")
                self.reply({"ok": True})

            def do_GET(self):
                if self.path.startswith("/v1/agents/permission/"):
                    self.reply({"decision": sys.argv[2], "pending": False})
                else:
                    self.reply({"ok": True})

            def log_message(self, *args):
                pass

        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        with open(sys.argv[1] + ".tmp", "w") as f:
            f.write(str(server.server_address[1]))
        import os
        os.rename(sys.argv[1] + ".tmp", sys.argv[1])
        server.serve_forever()
        """.write(to: serverScript, atomically: true, encoding: .utf8)

        let portFile = root.appendingPathComponent("port")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-I", serverScript.path, portFile.path, decision, postLog.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        server = process

        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if let text = try? String(contentsOf: portFile, encoding: .utf8), let port = Int(text) {
                try writePort(port)
                return
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        XCTFail("test server did not start")
    }

    private func postedEvents() throws -> [[String: Any]] {
        let text = try String(contentsOf: postLog, encoding: .utf8)
        return text.split(separator: "\n").compactMap {
            try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
        }
    }

    // MARK: - Sample payloads (from each agent's hook reference)

    private let codexPermission = #"{"session_id":"c1","hook_event_name":"PermissionRequest","cwd":"/tmp","model":"gpt-5","turn_id":"t1","tool_name":"Bash","tool_input":{"command":"npm test","description":"Run tests"}}"#
    private let qwenPermission = #"{"session_id":"q1","hook_event_name":"PermissionRequest","cwd":"/tmp","tool_name":"run_shell_command","tool_input":{"command":"npm test"},"permission_mode":"default"}"#
    private let copilotPermission = #"{"sessionId":"p1","timestamp":1760000000000,"cwd":"/tmp","toolName":"bash","toolInput":{"command":"npm test"}}"#

    private var monitorOnlySamples: [(String, String, String)] {
        [
            ("gemini", "Notification", #"{"session_id":"g1","hook_event_name":"Notification","cwd":"/tmp","notification_type":"ToolPermission","message":"Allow run_shell_command?","details":{}}"#),
            ("gemini", "BeforeTool", #"{"session_id":"g1","hook_event_name":"BeforeTool","cwd":"/tmp","tool_name":"run_shell_command","tool_input":{"command":"ls"}}"#),
            ("crush", "PermissionRequest", #"{"event":"PermissionRequest","hook_event_name":"PermissionRequest","session_id":"k1","cwd":"/tmp","tool_name":"bash","tool_input":{"command":"rm -rf build"}}"#),
            ("droid", "Notification", #"{"session_id":"d1","hook_event_name":"Notification","cwd":"/tmp","permission_mode":"default","notification_type":"permission_prompt","message":"Droid needs your permission"}"#),
            ("opencode", "permission.asked", #"{"session_id":"o1","cwd":"/tmp","tool_name":"bash","message":"git push"}"#),
            ("kilo", "session.idle", #"{"session_id":"o2","cwd":"/tmp"}"#),
            ("cursor", "beforeShellExecution", #"{"conversation_id":"u1","command":"ls"}"#),
            ("grok", "PostToolUse", #"{"session_id":"x1","hook_event_name":"PostToolUse","tool_name":"bash"}"#),
        ]
    }

    // MARK: - Tests

    func testEveryAgentExitsZeroWithoutAnswerWhenNotchFlowIsNotRunning() throws {
        let samples = monitorOnlySamples + [
            ("codex", "PermissionRequest", codexPermission),
            ("qwen", "PermissionRequest", qwenPermission),
            ("copilot", "permissionRequest", copilotPermission),
            ("copilot", "preToolUse", "not json"),
        ]
        let start = Date()
        for (sample, run) in zip(samples, runAll(samples)) {
            let run = try XCTUnwrap(run, "\(sample.0) \(sample.1)")
            XCTAssertEqual(run.status, 0, "\(sample.0) \(sample.1)")
            let expected = sample.0 == "cursor" ? "{\"continue\":true}\n" : ""
            XCTAssertEqual(run.stdout, expected, "\(sample.0) \(sample.1)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 10, "a prompt must not wait when nobody can answer")
    }

    func testCopilotExitsZeroWithoutNotchFlowConfig() throws {
        try FileManager.default.removeItem(at: supportFolder.appendingPathComponent("api.json"))
        let run = try runHook(agent: "copilot", event: "preToolUse", payload: "{")
        XCTAssertEqual(run.status, 0)
        XCTAssertEqual(run.stdout, "")
    }

    func testMonitorOnlyAgentsNeverPrintADecisionEvenWhenNotchFlowAllows() throws {
        try startServer(decision: "allow")
        for (sample, run) in zip(monitorOnlySamples, runAll(monitorOnlySamples)) {
            let run = try XCTUnwrap(run)
            XCTAssertEqual(run.status, 0, "\(sample.0) \(sample.1)")
            XCTAssertFalse(run.stdout.contains("behavior"), "\(sample.0) \(sample.1)")
            XCTAssertFalse(run.stdout.contains("allow"), "\(sample.0) \(sample.1)")
        }
        let events = try postedEvents()
        let byAgent = Dictionary(events.map { ($0["agent"] as? String ?? "", $0["event"] as? String ?? "") }) { a, _ in a }
        XCTAssertEqual(byAgent["crush"], "attention")
        XCTAssertEqual(byAgent["droid"], "attention")
        XCTAssertEqual(byAgent["opencode"], "attention")
        XCTAssertEqual(byAgent["kilo"], "done")
        XCTAssertTrue(events.allSatisfy { ($0["permissionId"] as? String ?? "").isEmpty })
    }

    func testCodexQwenAndCopilotPrintTheirAllowAnswer() throws {
        try startServer(decision: "allow")
        let runs = runAll([
            ("codex", "PermissionRequest", codexPermission),
            ("qwen", "PermissionRequest", qwenPermission),
            ("copilot", "permissionRequest", copilotPermission),
        ])
        let claudeShaped = #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#
        XCTAssertEqual(runs[0]?.stdout, claudeShaped + "\n")
        XCTAssertEqual(runs[1]?.stdout, claudeShaped + "\n")
        XCTAssertEqual(runs[2]?.stdout, #"{"behavior":"allow"}"# + "\n")
        XCTAssertEqual(runs.map { $0?.status }, [0, 0, 0])

        let permissions = try postedEvents().filter { $0["event"] as? String == "permission" }
        XCTAssertEqual(permissions.count, 3)
        XCTAssertEqual(Set(permissions.compactMap { $0["summary"] as? String }), ["npm test"])
        XCTAssertEqual(Set(permissions.compactMap { $0["permissionId"] as? String }).count, 3)
    }

    func testCodexQwenAndCopilotPrintTheirDenyAnswer() throws {
        try startServer(decision: "deny")
        let runs = runAll([
            ("codex", "PermissionRequest", codexPermission),
            ("qwen", "PermissionRequest", qwenPermission),
            ("copilot", "permissionRequest", copilotPermission),
        ])
        let claudeShaped = #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Denied in NotchFlow"}}}"#
        XCTAssertEqual(runs[0]?.stdout, claudeShaped + "\n")
        XCTAssertEqual(runs[1]?.stdout, claudeShaped + "\n")
        XCTAssertEqual(runs[2]?.stdout, #"{"behavior":"deny","message":"Denied in NotchFlow"}"# + "\n")
    }

    func testEventNamesMapToNotchFlowEvents() throws {
        try startServer(decision: "allow")
        let samples: [(String, String, String)] = [
            ("codex", "UserPromptSubmit", #"{"session_id":"c2","hook_event_name":"UserPromptSubmit","prompt":"private idea"}"#),
            ("codex", "Stop", #"{"session_id":"c3","hook_event_name":"Stop","stop_hook_active":false}"#),
            ("copilot", "preToolUse", #"{"sessionId":"p2","cwd":"/tmp","toolName":"bash","toolArgs":"{\"command\":\"git status\"}"}"#),
            ("copilot", "agentStop", #"{"sessionId":"p3","stopReason":"end_turn"}"#),
            ("qwen", "Notification", #"{"session_id":"q2","hook_event_name":"Notification","notification_type":"permission_prompt","message":"Qwen needs permission"}"#),
            ("gemini", "AfterAgent", #"{"session_id":"g2","hook_event_name":"AfterAgent","prompt":"x","prompt_response":"y"}"#),
            ("crush", "TurnEnd", #"{"hook_event_name":"TurnEnd","session_id":"k2"}"#),
            ("droid", "PreToolUse", #"{"session_id":"d2","hook_event_name":"PreToolUse","tool_name":"Execute","tool_input":{"command":"make"}}"#),
        ]
        _ = runAll(samples)
        let bySession = Dictionary(try postedEvents().map { ($0["sessionId"] as? String ?? "", $0) }) { a, _ in a }
        XCTAssertEqual(bySession["c2"]?["event"] as? String, "session.started")
        XCTAssertEqual(bySession["c2"]?["summary"] as? String, "", "typed prompts never reach the notch")
        XCTAssertEqual(bySession["c3"]?["event"] as? String, "done")
        XCTAssertEqual(bySession["p2"]?["event"] as? String, "tool")
        XCTAssertEqual(bySession["p2"]?["detail"] as? String, "bash: git status")
        XCTAssertEqual(bySession["p3"]?["event"] as? String, "done")
        XCTAssertEqual(bySession["q2"]?["event"] as? String, "notification")
        XCTAssertEqual(bySession["g2"]?["event"] as? String, "done")
        XCTAssertEqual(bySession["k2"]?["event"] as? String, "done")
        XCTAssertEqual(bySession["d2"]?["event"] as? String, "tool")
        XCTAssertEqual(bySession["d2"]?["title"] as? String, "Droid")
    }

    func testHookScriptAlwaysExitsZero() throws {
        let script = try String(contentsOf: Self.scriptURL, encoding: .utf8)
        XCTAssertTrue(script.contains("trap 'exit 0' EXIT"))
        XCTAssertTrue(script.contains("answers_in_notch"))
    }
}
