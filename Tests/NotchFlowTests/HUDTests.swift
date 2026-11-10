import XCTest
@testable import NotchFlow

final class SystemDefinedKeyEventTests: XCTestCase {
    private func data1(key: Int, state: Int, repeats: Bool = false) -> Int {
        (key << 16) | (state << 8) | (repeats ? 1 : 0)
    }

    func testDecodesBrightnessUpKeyDown() throws {
        let event = try XCTUnwrap(SystemDefinedKeyEvent(subtype: 8, data1: data1(key: 2, state: 0x0A)))
        XCTAssertEqual(event.keyCode, SystemDefinedKeyEvent.brightnessUpKeyCode)
        XCTAssertTrue(event.isKeyDown)
        XCTAssertFalse(event.isRepeat)
        XCTAssertTrue(event.isBrightnessKeyDown)
    }

    func testDecodesBrightnessDownKeyRepeat() throws {
        let event = try XCTUnwrap(SystemDefinedKeyEvent(subtype: 8, data1: data1(key: 3, state: 0x0A, repeats: true)))
        XCTAssertEqual(event.keyCode, SystemDefinedKeyEvent.brightnessDownKeyCode)
        XCTAssertTrue(event.isRepeat)
        XCTAssertTrue(event.isBrightnessKeyDown)
    }

    func testKeyUpIsNotAPress() throws {
        let event = try XCTUnwrap(SystemDefinedKeyEvent(subtype: 8, data1: data1(key: 2, state: 0x0B)))
        XCTAssertFalse(event.isKeyDown)
        XCTAssertFalse(event.isBrightnessKeyDown)
    }

    func testOtherMediaKeysAreIgnored() throws {
        // NX_KEYTYPE_PLAY = 16, NX_KEYTYPE_SOUND_UP = 0
        for key in [16, 0, 1, 7] {
            let event = try XCTUnwrap(SystemDefinedKeyEvent(subtype: 8, data1: data1(key: key, state: 0x0A)))
            XCTAssertFalse(event.isBrightnessKeyDown, "key \(key)")
        }
    }

    func testOtherSubtypesAreNotKeyEvents() {
        XCTAssertNil(SystemDefinedKeyEvent(subtype: 7, data1: data1(key: 2, state: 0x0A)))
        XCTAssertNil(SystemDefinedKeyEvent(subtype: 0, data1: data1(key: 2, state: 0x0A)))
    }
}

final class HUDSymbolTests: XCTestCase {
    func testVolumeSymbols() {
        XCTAssertEqual(HUDSymbol.volume(level: 0.8, isMuted: true), "speaker.slash.fill")
        XCTAssertEqual(HUDSymbol.volume(level: 0, isMuted: false), "speaker.slash.fill")
        XCTAssertEqual(HUDSymbol.volume(level: 0.1, isMuted: false), "speaker.wave.1.fill")
        XCTAssertEqual(HUDSymbol.volume(level: 0.5, isMuted: false), "speaker.wave.2.fill")
        XCTAssertEqual(HUDSymbol.volume(level: 0.9, isMuted: false), "speaker.wave.3.fill")
        XCTAssertEqual(HUDSymbol.volume(level: 1, isMuted: false), "speaker.wave.3.fill")
    }

    func testBrightnessSymbols() {
        XCTAssertEqual(HUDSymbol.brightness(level: 0.2), "sun.min.fill")
        XCTAssertEqual(HUDSymbol.brightness(level: 0.75), "sun.max.fill")
        XCTAssertEqual(HUDSymbol.name(kind: .brightness, level: 0.75, isMuted: false), "sun.max.fill")
    }

    func testMutedStateShowsAnEmptyBarAndClampsLevels() {
        let expires = Date(timeIntervalSince1970: 10)
        let muted = HUDOverlayState(reading: HUDLevelReading(kind: .volume, level: 0.6, isMuted: true), expiresAt: expires)
        XCTAssertEqual(muted.displayLevel, 0)
        XCTAssertEqual(muted.symbolName, "speaker.slash.fill")
        let loud = HUDOverlayState(reading: HUDLevelReading(kind: .volume, level: 1.4), expiresAt: expires)
        XCTAssertEqual(loud.value, 1)
    }
}

@MainActor
final class HUDLiveActivityPriorityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)

    private func hud(expiresIn seconds: TimeInterval) -> HUDOverlayState {
        HUDOverlayState(
            reading: HUDLevelReading(kind: .volume, level: 0.5),
            expiresAt: now.addingTimeInterval(seconds)
        )
    }

    private func agent(needsAttention: Bool) -> AgentSessionActivity {
        AgentSessionActivity(
            id: "s1",
            agent: .claude,
            title: "Claude Code",
            detail: "",
            phase: needsAttention ? .waitingPermission : .running,
            updatedAt: now,
            needsAttention: needsAttention,
            showsNotchApproval: needsAttention
        )
    }

    private let timer = FocusTimerActivity(
        formattedTime: "12:00",
        progress: 0.4,
        isRunning: true,
        modeLabel: "Focus",
        totalSeconds: 1500,
        mode: .countdown
    )

    func testActiveHUDOutranksMediaTimerAndRunningAgent() {
        let level = hud(expiresIn: 1)
        let resolved = LiveActivityResolver.resolve(
            agentSession: agent(needsAttention: false),
            timer: timer,
            notification: nil,
            hud: level,
            showsMedia: true,
            now: now
        )
        XCTAssertEqual(resolved, .hud(level))
    }

    func testExpiredHUDReturnsThePreviousActivity() {
        let resolved = LiveActivityResolver.resolve(
            agentSession: nil,
            timer: nil,
            notification: nil,
            hud: hud(expiresIn: -0.1),
            showsMedia: true,
            now: now
        )
        XCTAssertEqual(resolved, .media)

        let nothing = LiveActivityResolver.resolve(
            agentSession: nil,
            timer: nil,
            notification: nil,
            hud: hud(expiresIn: 0),
            showsMedia: false,
            now: now
        )
        XCTAssertNil(nothing)
    }

    func testHUDAloneShowsInTheWings() {
        let level = hud(expiresIn: HUDManager.visibleDuration)
        let resolved = LiveActivityResolver.resolve(
            agentSession: nil,
            timer: nil,
            notification: nil,
            hud: level,
            showsMedia: false,
            now: now
        )
        XCTAssertEqual(resolved, .hud(level))
    }

    func testPermissionPromptStaysAboveHUD() {
        let prompt = agent(needsAttention: true)
        let resolved = LiveActivityResolver.resolve(
            agentSession: prompt,
            timer: nil,
            notification: nil,
            hud: hud(expiresIn: 1),
            showsMedia: false,
            now: now
        )
        XCTAssertEqual(resolved, .agentSession(prompt))
    }

    func testHUDRightWingFitsTheLevelBar() {
        let width = IdleHUDMetrics.preferredRightWingWidth
        XCTAssertGreaterThanOrEqual(width, IdleHUDMetrics.barWidth)
        XCTAssertGreaterThan(width, NotchFlowConstants.idleWingProtrusion)
        XCTAssertLessThanOrEqual(width, NotchFlowConstants.maxIdleCallWingWidth)
    }
}

@MainActor
private final class FakeLevelSource: HUDLevelSource {
    var onLevel: ((HUDLevelReading) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    var isRunning: Bool { startCount > stopCount }

    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
}

@MainActor
final class HUDManagerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 5_000)
    private var created: [FakeLevelSource] = []

    private func makeManager() -> HUDManager {
        HUDManager(
            makeSources: { [unowned self] in
                let source = FakeLevelSource()
                self.created.append(source)
                return [source]
            },
            now: { [now] in now }
        )
    }

    func testDisabledManagerInstallsNothing() {
        let manager = makeManager()
        XCTAssertFalse(manager.isListening)
        XCTAssertTrue(created.isEmpty)
        manager.setEnabled(false)
        XCTAssertTrue(created.isEmpty)
    }

    func testEnablingStartsSourcesOnce() {
        let manager = makeManager()
        manager.setEnabled(true)
        manager.setEnabled(true)
        XCTAssertEqual(created.count, 1)
        XCTAssertEqual(created.first?.startCount, 1)
        XCTAssertTrue(manager.isListening)
    }

    func testReadingShowsLevelUntilTheExpiry() throws {
        let manager = makeManager()
        var published: [HUDOverlayState?] = []
        manager.onHUDChange = { published.append($0) }
        manager.setEnabled(true)
        let source = try XCTUnwrap(created.first)

        source.onLevel?(HUDLevelReading(kind: .brightness, level: 0.42))

        let state = try XCTUnwrap(manager.state)
        XCTAssertEqual(state.kind, .brightness)
        XCTAssertEqual(state.value, 0.42, accuracy: 0.0001)
        XCTAssertEqual(state.expiresAt, now.addingTimeInterval(HUDManager.visibleDuration))
        XCTAssertEqual(published.count, 1)
    }

    func testDisablingTearsDownListenersAndHidesTheLevel() throws {
        let manager = makeManager()
        var published: [HUDOverlayState?] = []
        manager.onHUDChange = { published.append($0) }
        manager.setEnabled(true)
        let source = try XCTUnwrap(created.first)
        source.onLevel?(HUDLevelReading(kind: .volume, level: 0.3))

        manager.setEnabled(false)

        XCTAssertFalse(source.isRunning)
        XCTAssertEqual(source.stopCount, 1)
        XCTAssertNil(source.onLevel)
        XCTAssertFalse(manager.isListening)
        XCTAssertNil(manager.state)
        XCTAssertEqual(published.count, 2)
        XCTAssertNil(published.last.flatMap { $0 })

        manager.show(HUDLevelReading(kind: .volume, level: 0.9))
        XCTAssertNil(manager.state, "a disabled HUD ignores late readings")
    }

    func testReEnablingCreatesFreshSources() {
        let manager = makeManager()
        manager.setEnabled(true)
        manager.setEnabled(false)
        manager.setEnabled(true)
        XCTAssertEqual(created.count, 2)
        XCTAssertFalse(created[0].isRunning)
        XCTAssertTrue(created[1].isRunning)
    }
}
