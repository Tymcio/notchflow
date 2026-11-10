import AppKit
import Foundation

/// Demo mode for recording marketing videos with fictional data.
///
/// Only DEBUG builds launched with `NOTCHFLOW_DEMO=1` turn it on; release builds compile
/// none of it (`isEnabled` is a constant `false`). In demo mode NotchFlow never reads or writes
/// the real install's data: notes and clipboard stay in memory, shelf and license files live in
/// a scratch folder in `NSTemporaryDirectory()` that is deleted on quit, and media, calendar,
/// agent sessions and usage meters show the fictional content below instead of being monitored.
/// `NOTCHFLOW_DEMO_AGENT_DELAY` sets the seconds before Claude Code asks for permission (default 3).
enum DemoMode {
    #if DEBUG
    static let environmentKey = "NOTCHFLOW_DEMO"
    static let agentDelayEnvironmentKey = "NOTCHFLOW_DEMO_AGENT_DELAY"
    static let defaultAgentPermissionDelay: TimeInterval = 3

    static let isEnabled = isEnabled(environment: ProcessInfo.processInfo.environment)

    /// Holds the demo's shelf files and license file; `nil` outside demo mode.
    static let scratchDirectory: URL? = isEnabled ? makeScratchDirectory() : nil

    static func isEnabled(environment: [String: String]) -> Bool {
        environment[environmentKey] == "1"
    }
    #else
    static let isEnabled = false
    static var scratchDirectory: URL? { nil }
    #endif
}

#if DEBUG
extension DemoMode {
    // MARK: - Scratch folder

    static func makeScratchDirectory(
        in parent: URL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    ) -> URL {
        let directory = parent.appendingPathComponent("NotchFlowDemo-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            NotchFlowLog.storage.error("Demo scratch folder failed: \(error.localizedDescription, privacy: .public)")
        }
        // Same spelling ShelfManager compares paths with (/var vs /private/var).
        return directory.resolvingSymlinksInPath()
    }

    static func removeScratchDirectory() {
        guard let scratchDirectory else { return }
        try? FileManager.default.removeItem(at: scratchDirectory)
    }

    static func agentPermissionDelay(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> TimeInterval {
        guard let raw = environment[agentDelayEnvironmentKey],
              let value = TimeInterval(raw.trimmingCharacters(in: .whitespaces)),
              value.isFinite, value >= 0 else {
            return defaultAgentPermissionDelay
        }
        return value
    }

    // MARK: - Fictional content

    static let agentWorkingDirectory = "~/Developer/shop"
    static let shelfFileNames = ["Pitch.key", "Invoice.pdf", "Assets.zip"]

    static func mediaState(now: Date = Date()) -> MediaPlaybackState {
        MediaPlaybackState(
            title: "Golden Hour",
            artist: "Northbound",
            album: "Long Light",
            artworkURL: nil,
            artworkData: artworkPNG(),
            isPlaying: true,
            elapsed: 48,
            duration: 3 * 60 + 24,
            bundleIdentifier: nil,
            lyricsSnippet: "We chase the light until it fades",
            positionSampledAt: now
        )
    }

    /// Album art drawn in code: a warm orange-to-purple sky with a soft sun.
    static func artworkPNG(side: Int = 320) -> Data? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        let size = CGFloat(side)

        let sky = [
            CGColor(srgbRed: 1.00, green: 0.66, blue: 0.30, alpha: 1),
            CGColor(srgbRed: 0.93, green: 0.38, blue: 0.42, alpha: 1),
            CGColor(srgbRed: 0.40, green: 0.20, blue: 0.60, alpha: 1),
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: sky, locations: [0, 0.5, 1]) {
            // Core Graphics has its origin at the bottom left: warm at the bottom, purple on top.
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: size * 0.2, y: 0),
                end: CGPoint(x: size * 0.8, y: size),
                options: []
            )
        }

        let sunCenter = CGPoint(x: size * 0.5, y: size * 0.42)
        let glow = [
            CGColor(srgbRed: 1.00, green: 0.90, blue: 0.70, alpha: 0.75),
            CGColor(srgbRed: 1.00, green: 0.80, blue: 0.55, alpha: 0),
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: glow, locations: [0, 1]) {
            context.drawRadialGradient(
                gradient,
                startCenter: sunCenter,
                startRadius: 0,
                endCenter: sunCenter,
                endRadius: size * 0.38,
                options: []
            )
        }
        let sunRadius = size * 0.15
        context.setFillColor(CGColor(srgbRed: 1.00, green: 0.93, blue: 0.80, alpha: 0.92))
        context.fillEllipse(in: CGRect(
            x: sunCenter.x - sunRadius,
            y: sunCenter.y - sunRadius,
            width: sunRadius * 2,
            height: sunRadius * 2
        ))

        guard let image = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    static func notes(now: Date = Date()) -> [NoteItem] {
        [
            NoteItem(text: "Launch checklist\nRecord the hero video", createdAt: now.addingTimeInterval(-25 * 60), isPinned: true),
            NoteItem(text: "Ideas\nDynamic Island for agents", createdAt: now.addingTimeInterval(-2 * 3600)),
        ]
    }

    static func clipboardEntries(now: Date = Date()) -> [ClipboardEntry] {
        [
            ClipboardEntry(kind: .text, value: "Record the hero video at golden hour", createdAt: now.addingTimeInterval(-4 * 60)),
            ClipboardEntry(kind: .url, value: "https://example.com/shop/checkout", createdAt: now.addingTimeInterval(-18 * 60)),
        ]
    }

    /// This week: two meetings today, a launch tomorrow and lunch on Friday.
    static func calendarEvents(now: Date = Date(), calendar: Calendar = .current) -> [CalendarEventPreview] {
        let today = calendar.startOfDay(for: now)
        func time(days: Int, hour: Int, minute: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: days, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        // Friday of this week, or the next one once the week's Friday has passed.
        let weekday = calendar.component(.weekday, from: today)
        let daysToFriday = (6 - weekday + 7) % 7

        return [
            CalendarEventPreview(
                id: "demo-standup",
                title: "Standup",
                startDate: time(days: 0, hour: 9, minute: 30),
                endDate: time(days: 0, hour: 9, minute: 45),
                meetingURL: nil
            ),
            CalendarEventPreview(
                id: "demo-design-review",
                title: "Design review",
                startDate: time(days: 0, hour: 14, minute: 0),
                endDate: time(days: 0, hour: 15, minute: 0),
                meetingURL: URL(string: "https://meet.example.com/design-review")
            ),
            CalendarEventPreview(
                id: "demo-ship-v2",
                title: "Ship v2",
                startDate: time(days: 1, hour: 10, minute: 0),
                endDate: time(days: 1, hour: 11, minute: 0),
                meetingURL: nil
            ),
            CalendarEventPreview(
                id: "demo-team-lunch",
                title: "Team lunch",
                startDate: time(days: daysToFriday, hour: 12, minute: 30),
                endDate: time(days: daysToFriday, hour: 13, minute: 30),
                meetingURL: nil
            ),
        ]
    }

    /// Reset times sit a few seconds/minutes past the round value, so the copy reads
    /// "2 hr, 14 min" and "4 days" when the island opens and then counts down for real.
    static func usageSnapshots(now: Date = Date()) -> [AgentUsageSnapshot] {
        let minute: TimeInterval = 60
        let hour = 60 * minute
        let day = 24 * hour
        func window(left: Double, resetsIn interval: TimeInterval) -> AgentUsageWindow {
            AgentUsageWindow(usedPercent: 100 - left, resetsAt: now.addingTimeInterval(interval))
        }
        return [
            AgentUsageSnapshot(
                agent: .claude,
                planName: "Max 5×",
                fiveHour: window(left: 62, resetsIn: 2 * hour + 14 * minute + 20),
                sevenDay: window(left: 81, resetsIn: 4 * day + 10 * minute),
                extra: nil,
                fetchedAt: now,
                status: .ready
            ),
            AgentUsageSnapshot(
                agent: .codex,
                planName: "Plus",
                fiveHour: window(left: 47, resetsIn: 3 * hour + 5 * minute + 20),
                sevenDay: window(left: 73, resetsIn: 5 * day + 10 * minute),
                extra: nil,
                fetchedAt: now,
                status: .ready
            ),
            AgentUsageSnapshot(
                agent: .cursor,
                planName: "Pro",
                fiveHour: nil,
                sevenDay: nil,
                extra: nil,
                meters: [AgentUsageMeter(label: "Included", window: window(left: 70, resetsIn: 12 * day + 10 * minute))],
                fetchedAt: now,
                status: .ready
            ),
        ]
    }

    static func licenseStatus(now: Date = Date()) -> LicenseStatus {
        LicenseStatus(
            tier: .lifetime,
            key: nil,
            validatedAt: now,
            expiresAt: nil,
            hasAgentsAddon: true,
            agentsKey: nil,
            agentsValidatedAt: now
        )
    }

    // MARK: - Seeding

    /// Pins small placeholder files created in `filesDirectory` (inside the demo scratch folder).
    @MainActor
    static func seedShelf(_ manager: ShelfManager, filesDirectory: URL) {
        try? FileManager.default.createDirectory(at: filesDirectory, withIntermediateDirectories: true)
        // Each new pin goes first, so pin in reverse to list them in `shelfFileNames` order.
        for name in shelfFileNames.reversed() {
            let url = filesDirectory.appendingPathComponent(name)
            try? Data("NotchFlow demo file\n".utf8).write(to: url)
            _ = manager.pinURL(url, isPremium: true)
        }
    }

    /// Keeps the agent scenario alive for the whole run.
    @MainActor static var agentScenario: DemoAgentScenario?
}

/// Codex keeps working while Claude Code asks to run `npm test`. Allow in the island runs it
/// and finishes the session a few seconds later; Deny ends it. No hook process exists:
/// everything goes through `AgentSessionManager`'s in-memory event API.
@MainActor
final class DemoAgentScenario {
    static let codexSessionID = "demo-codex"
    static let claudeSessionID = "demo-claude"
    static let claudePermissionID = "demo-claude-npm-test"

    private let manager: AgentSessionManager
    private let finishDelay: Duration
    private var tasks: [Task<Void, Never>] = []

    init(manager: AgentSessionManager, finishDelay: Duration = .seconds(4)) {
        self.manager = manager
        self.finishDelay = finishDelay
    }

    func start(permissionDelay: TimeInterval) {
        // Nothing reports progress in demo mode, so sessions must not time out, and jumping
        // must not bring a real terminal or editor forward.
        manager.finishesQuietSessions = false
        manager.jumpsToAgentApps = false
        manager.onPermissionDecided = { [weak self] id, decision in
            self?.permissionDecided(id: id, decision: decision)
        }

        manager.ingestEvent([
            "agent": AgentKind.codex.rawValue,
            "event": "tool",
            "sessionId": Self.codexSessionID,
            "detail": "Refactoring payment tests",
            "cwd": DemoMode.agentWorkingDirectory,
        ])

        tasks.append(Task { [weak self] in
            try? await Task.sleep(for: .seconds(permissionDelay))
            guard !Task.isCancelled else { return }
            self?.requestClaudePermission()
        })
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks = []
    }

    func requestClaudePermission() {
        manager.ingestEvent([
            "agent": AgentKind.claude.rawValue,
            "event": "permission",
            "sessionId": Self.claudeSessionID,
            "permissionId": Self.claudePermissionID,
            "toolName": "Bash",
            "summary": "npm test",
            "cwd": DemoMode.agentWorkingDirectory,
        ])
    }

    /// Deny needs nothing more: the manager already shows "Denied" and clears the session.
    private func permissionDecided(id: String, decision: AgentPermissionDecision) {
        guard id == Self.claudePermissionID, decision == .allow else { return }
        manager.ingestEvent([
            "agent": AgentKind.claude.rawValue,
            "event": "tool",
            "sessionId": Self.claudeSessionID,
            "detail": "Running npm test",
            "cwd": DemoMode.agentWorkingDirectory,
        ])
        let finishDelay = finishDelay
        tasks.append(Task { [weak self] in
            try? await Task.sleep(for: finishDelay)
            guard !Task.isCancelled else { return }
            self?.manager.ingestEvent([
                "agent": AgentKind.claude.rawValue,
                "event": "done",
                "sessionId": DemoAgentScenario.claudeSessionID,
            ])
        })
    }
}

extension AppState {
    /// Replaces `start()` in demo mode: fictional content, and no monitoring of players,
    /// calendars, notifications, the clipboard, licenses, agent hooks, usage APIs or the
    /// volume / brightness keys.
    func startDemo() {
        let now = Date()
        licenseStatus = DemoMode.licenseStatus(now: now)
        settings.isPremiumEnabled = isPremium
        displayManager.refreshGeometryNow()
        // Mute detection for the timer UI only; demo mode never sounds or posts an alarm.
        focusTimerManager.startMonitoring()

        mediaMonitor.showSimulatedTrack(DemoMode.mediaState(now: now))
        calendarManager.useFixedEvents(DemoMode.calendarEvents(now: now), now: now)
        calendarAccessGranted = true

        notesManager.setNotes(DemoMode.notes(now: now))
        notes = notesManager.notes
        if let directory = DemoMode.scratchDirectory {
            DemoMode.seedShelf(
                shelfManager,
                filesDirectory: directory.appendingPathComponent("Shelf/Demo files", isDirectory: true)
            )
        }
        shelfItems = shelfManager.items
        clipboardManager.setEntriesForTesting(DemoMode.clipboardEntries(now: now))
        clipboardEntries = clipboardManager.entries

        agentUsageMonitor.showFixedSnapshots(DemoMode.usageSnapshots(now: now))
        let scenario = DemoAgentScenario(manager: agentSessionManager)
        DemoMode.agentScenario = scenario
        scenario.start(permissionDelay: DemoMode.agentPermissionDelay())
    }
}
#endif
