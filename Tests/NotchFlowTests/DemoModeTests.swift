import AppKit
import XCTest
@testable import NotchFlow

@MainActor
final class DemoModeTests: XCTestCase {
    func testDisabledWithoutEnvironmentVariable() throws {
        XCTAssertFalse(DemoMode.isEnabled(environment: [:]))
        XCTAssertFalse(DemoMode.isEnabled(environment: ["NOTCHFLOW_DEMO": "0"]))
        XCTAssertTrue(DemoMode.isEnabled(environment: ["NOTCHFLOW_DEMO": "1"]))

        try XCTSkipIf(
            ProcessInfo.processInfo.environment["NOTCHFLOW_DEMO"] != nil,
            "NOTCHFLOW_DEMO is set for this test run"
        )
        XCTAssertFalse(DemoMode.isEnabled)
        XCTAssertNil(DemoMode.scratchDirectory)
    }

    func testAgentPermissionDelayFromEnvironment() {
        XCTAssertEqual(DemoMode.agentPermissionDelay(environment: [:]), 3)
        XCTAssertEqual(DemoMode.agentPermissionDelay(environment: ["NOTCHFLOW_DEMO_AGENT_DELAY": "7.5"]), 7.5)
        XCTAssertEqual(DemoMode.agentPermissionDelay(environment: ["NOTCHFLOW_DEMO_AGENT_DELAY": "soon"]), 3)
        XCTAssertEqual(DemoMode.agentPermissionDelay(environment: ["NOTCHFLOW_DEMO_AGENT_DELAY": "-1"]), 3)
    }

    func testMediaSeedingPlaysFictionalTrackAndTransportStaysInMemory() throws {
        let monitor = MediaMonitor()
        var published: MediaPlaybackState?
        monitor.onStateChange = { published = $0 }
        let now = Date()

        monitor.showSimulatedTrack(DemoMode.mediaState(now: now))

        let state = try XCTUnwrap(published)
        XCTAssertEqual(state.title, "Golden Hour")
        XCTAssertEqual(state.artist, "Northbound")
        XCTAssertEqual(state.duration, 204)
        XCTAssertEqual(state.elapsed, 48)
        XCTAssertTrue(state.isPlaying)
        XCTAssertNil(state.bundleIdentifier)
        XCTAssertEqual(state.lyricsSnippet, "We chase the light until it fades")
        XCTAssertEqual(state.interpolatedPosition(at: now.addingTimeInterval(10)), 58, accuracy: 0.001)
        let artwork = try XCTUnwrap(state.artworkData)
        XCTAssertNotNil(NSImage(data: artwork))

        monitor.togglePlayPause()
        XCTAssertEqual(published?.isPlaying, false)
        XCTAssertEqual(published?.title, "Golden Hour")
        XCTAssertGreaterThanOrEqual(published?.elapsed ?? 0, 48)

        monitor.seek(to: 120)
        XCTAssertEqual(published?.elapsed, 120)
        XCTAssertEqual(published?.isPlaying, false)

        monitor.togglePlayPause()
        XCTAssertEqual(published?.isPlaying, true)
    }

    func testAgentScenarioRunsCodexAndAnswersClaudePermission() async throws {
        let manager = AgentSessionManager()
        let scenario = DemoAgentScenario(manager: manager, finishDelay: .milliseconds(20))
        defer { scenario.stop() }

        scenario.start(permissionDelay: 3600)
        XCTAssertFalse(manager.jumpsToAgentApps)
        XCTAssertFalse(manager.finishesQuietSessions)

        let codex = try XCTUnwrap(manager.sessions.first { $0.id == DemoAgentScenario.codexSessionID })
        XCTAssertEqual(codex.agent, .codex)
        XCTAssertEqual(codex.phase, .running)
        XCTAssertEqual(codex.detail, "Refactoring payment tests")
        XCTAssertEqual(codex.cwd, "~/Developer/shop")

        scenario.requestClaudePermission()
        let waiting = try XCTUnwrap(manager.sessions.first { $0.id == DemoAgentScenario.claudeSessionID })
        XCTAssertEqual(waiting.agent, .claude)
        XCTAssertEqual(waiting.phase, .waitingPermission)
        XCTAssertEqual(waiting.permission?.toolName, "Bash")
        XCTAssertEqual(waiting.permission?.summary, "npm test")
        XCTAssertEqual(waiting.cwd, "~/Developer/shop")
        XCTAssertEqual(manager.primaryActivity?.id, DemoAgentScenario.claudeSessionID)

        manager.decidePermission(id: DemoAgentScenario.claudePermissionID, decision: .allow)
        let running = try XCTUnwrap(manager.sessions.first { $0.id == DemoAgentScenario.claudeSessionID })
        XCTAssertEqual(running.phase, .running)
        XCTAssertEqual(running.detail, "Running npm test")
        XCTAssertNil(running.permission)

        try await Task.sleep(for: .milliseconds(300))
        let finished = try XCTUnwrap(manager.sessions.first { $0.id == DemoAgentScenario.claudeSessionID })
        XCTAssertEqual(finished.phase, .done)
        XCTAssertEqual(manager.sessions.first { $0.id == DemoAgentScenario.codexSessionID }?.phase, .running)
    }

    func testAgentScenarioDenyEndsClaudeSession() throws {
        let manager = AgentSessionManager()
        let scenario = DemoAgentScenario(manager: manager, finishDelay: .milliseconds(20))
        defer { scenario.stop() }
        scenario.start(permissionDelay: 3600)
        scenario.requestClaudePermission()

        manager.decidePermission(id: DemoAgentScenario.claudePermissionID, decision: .deny)

        let denied = try XCTUnwrap(manager.sessions.first { $0.id == DemoAgentScenario.claudeSessionID })
        XCTAssertEqual(denied.phase, .error)
        XCTAssertNil(denied.permission)
    }

    func testUsageSeedingShowsFixedMetersWithoutPolling() throws {
        let monitor = AgentUsageMonitor(removesLegacyTokenCaches: false)
        var changes = 0
        monitor.onChange = { changes += 1 }
        let now = Date()

        monitor.showFixedSnapshots(DemoMode.usageSnapshots(now: now))
        monitor.setEnabled(true)

        XCTAssertEqual(changes, 1)
        XCTAssertFalse(monitor.isRefreshing)
        XCTAssertEqual(monitor.snapshots.map(\.agent), [.claude, .codex, .cursor])

        let claude = try XCTUnwrap(monitor.claude)
        XCTAssertEqual(claude.planName, "Max 5×")
        XCTAssertEqual(claude.fiveHour?.remainingPercent, 62)
        XCTAssertEqual(claude.sevenDay?.remainingPercent, 81)
        let claudeReset = try XCTUnwrap(claude.fiveHour?.resetsAt).timeIntervalSince(now)
        XCTAssertEqual(claudeReset, (2 * 60 + 14) * 60, accuracy: 60)
        let weeklyReset = try XCTUnwrap(claude.sevenDay?.resetsAt).timeIntervalSince(now)
        XCTAssertEqual(weeklyReset, 4 * 86_400, accuracy: 3600)
        XCTAssertEqual(monitor.idleHint(for: .claude)?.remainingPercent, 62)

        let codex = try XCTUnwrap(monitor.codex)
        XCTAssertEqual(codex.planName, "Plus")
        XCTAssertEqual(codex.fiveHour?.remainingPercent, 47)
        XCTAssertEqual(codex.sevenDay?.remainingPercent, 73)
        XCTAssertEqual(monitor.idleHint(for: .codex)?.remainingPercent, 47)

        let cursor = try XCTUnwrap(monitor.cursor)
        XCTAssertEqual(cursor.planName, "Pro")
        XCTAssertEqual(cursor.meters.map(\.label), ["Included"])
        XCTAssertEqual(cursor.meters.first?.window.remainingPercent, 70)
        let cursorReset = try XCTUnwrap(cursor.meters.first?.window.resetsAt).timeIntervalSince(now)
        XCTAssertEqual(cursorReset, 12 * 86_400, accuracy: 3600)
    }

    func testCalendarSeedingServesFixedEventsWithoutEventKit() async throws {
        let calendar = Calendar.current
        // A Tuesday at 10:00, so "today", "tomorrow" and "Friday" are three different days.
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 10)))
        let manager = CalendarManager()

        manager.useFixedEvents(DemoMode.calendarEvents(now: now, calendar: calendar), now: now)

        XCTAssertTrue(manager.hasAccess)
        XCTAssertEqual(manager.upcomingEvent?.title, "Design review")
        XCTAssertEqual(manager.dayEvents.map(\.title), ["Design review"])
        let today = await manager.events(on: now)
        XCTAssertEqual(today.map(\.title), ["Standup", "Design review"])
        let tomorrow = await manager.events(on: now.addingTimeInterval(86_400))
        XCTAssertEqual(tomorrow.map(\.title), ["Ship v2"])
        let friday = await manager.events(on: now.addingTimeInterval(3 * 86_400))
        XCTAssertEqual(friday.map(\.title), ["Team lunch"])
        XCTAssertEqual(calendar.component(.hour, from: try XCTUnwrap(friday.first).startDate), 12)
        XCTAssertEqual(calendar.component(.minute, from: try XCTUnwrap(friday.first).startDate), 30)
    }

    func testNotesStayInMemory() {
        let manager = NotesManager(storageURL: nil)
        XCTAssertTrue(manager.notes.isEmpty)

        manager.setNotes(DemoMode.notes())

        XCTAssertEqual(manager.notes.map(\.text), [
            "Launch checklist\nRecord the hero video",
            "Ideas\nDynamic Island for agents",
        ])
        XCTAssertTrue(manager.notes[0].isPinned)
    }

    func testShelfSeedingPinsPlaceholderFilesInsideScratchFolder() throws {
        let scratch = DemoMode.makeScratchDirectory(in: FileManager.default.temporaryDirectory)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let shelfDirectory = scratch.appendingPathComponent("Shelf", isDirectory: true)
        let manager = ShelfManager(directory: shelfDirectory)

        DemoMode.seedShelf(manager, filesDirectory: shelfDirectory.appendingPathComponent("Demo files", isDirectory: true))

        XCTAssertEqual(manager.pinnedItems.map(\.displayName), ["Pitch.key", "Invoice.pdf", "Assets.zip"])
        for item in manager.pinnedItems {
            let original = try XCTUnwrap(item.originalPath)
            XCTAssertTrue(original.hasPrefix(scratch.path), original)
            XCTAssertTrue(item.url.path.hasPrefix(scratch.path), item.url.path)
            XCTAssertTrue(FileManager.default.fileExists(atPath: original))
        }
    }
}
