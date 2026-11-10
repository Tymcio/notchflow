import XCTest
@testable import NotchFlow

/// Loads the OpenCode / Kilo plugin in Node (when installed) and drives both plugin APIs with
/// fake events. The hook it runs is a stand-in that records each call.
final class AgentPluginTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nf-plugin-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("calls"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var nodeURL: URL? {
        ["/opt/homebrew/bin/node", "/usr/local/bin/node"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map(URL.init(fileURLWithPath:))
    }

    private let driver = """
    const plugin = (await import(process.argv[2])).default
    const v1 = await plugin.server({ directory: "/tmp/v1" })
    const status = (id, type) => ({ event: { type: "session.status", properties: { sessionID: id, status: { type } } } })
    await v1.event(status("s1", "busy"))
    await v1.event(status("s1", "busy"))
    await v1["tool.execute.before"]({ tool: "bash", sessionID: "s1", callID: "c1" }, { args: { command: "ls" } })
    await v1.event({ event: { type: "permission.asked", properties: { sessionID: "s1", permission: "bash", patterns: ["git push"] } } })
    await v1.event({ event: { type: "session.idle", properties: { sessionID: "s1" } } })
    await v1.event(status("s1", "idle"))
    await v1.event(null)
    await v1.event({ event: { type: "session.status" } })

    let toolHook = null
    const events = [
      { type: "session.status", data: { sessionID: "s2", status: { type: "busy" } } },
      { type: "session.execution.failed", data: { sessionID: "s2", error: { message: "boom" } } },
    ]
    const ctx = {
      location: { directory: "/tmp/v2" },
      event: { async *subscribe() { for (const e of events) yield e } },
      tool: { hook: async (name, callback) => { toolHook = callback; return { dispose() {} } } },
    }
    const cleanup = await plugin.setup(ctx)
    toolHook({ tool: "read", sessionID: "s2", input: { filePath: "/x" } })
    toolHook(undefined)
    cleanup()
    await plugin.setup({})
    """

    func testPluginReportsEachEventOnceAndNeverThrows() throws {
        guard let node = nodeURL else { throw XCTSkip("node is not installed") }
        let calls = root.appendingPathComponent("calls")
        let hook = root.appendingPathComponent("hook.sh")
        try """
        #!/bin/sh
        f=$(mktemp "\(calls.path)/call.XXXXXX")
        { printf '%s %s\\n' "$NOTCHFLOW_AGENT" "$NOTCHFLOW_HOOK_EVENT"; cat; } > "$f"
        """.write(to: hook, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)

        let plugin = root.appendingPathComponent("notchflow.mjs")
        try AgentHooksInstaller.pluginSource(agent: .kilo, scriptPath: hook.path)
            .write(to: plugin, atomically: true, encoding: .utf8)
        let driverURL = root.appendingPathComponent("driver.mjs")
        try driver.write(to: driverURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = node
        process.arguments = [driverURL.path, plugin.absoluteString]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        let stderr = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, stderr)

        var lines: [String] = []
        let deadline = Date().addingTimeInterval(2)
        repeat {
            let files = (try? FileManager.default.contentsOfDirectory(at: calls, includingPropertiesForKeys: nil)) ?? []
            lines = files.compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            if lines.count >= 7, lines.allSatisfy({ $0.contains("{") }) { break }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline

        let headers = lines.map { String($0.prefix { $0 != "\n" }) }.sorted()
        XCTAssertEqual(headers, [
            "kilo permission.asked",
            "kilo session.busy",
            "kilo session.busy",
            "kilo session.error",
            "kilo session.idle",
            "kilo tool.execute.before",
            "kilo tool.execute.before",
        ])
        XCTAssertTrue(lines.contains { $0.contains(#""tool_input":{"command":"ls"}"#) })
        XCTAssertTrue(lines.contains { $0.contains(#""message":"boom""#) })
        XCTAssertTrue(lines.contains { $0.contains(#""message":"git push""#) })
    }
}
