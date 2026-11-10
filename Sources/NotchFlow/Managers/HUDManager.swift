import AppKit
import Foundation

enum HUDKind: String, Sendable {
    case volume
    case brightness
}

/// One level read from the system: output volume (with mute) or built-in display brightness.
struct HUDLevelReading: Equatable, Sendable {
    let kind: HUDKind
    /// 0...1
    let level: Double
    var isMuted = false
}

struct HUDOverlayState: Equatable, Sendable {
    let kind: HUDKind
    /// 0...1
    let value: Double
    let isMuted: Bool
    let expiresAt: Date

    init(reading: HUDLevelReading, expiresAt: Date) {
        kind = reading.kind
        value = min(max(reading.level, 0), 1)
        isMuted = reading.isMuted
        self.expiresAt = expiresAt
    }

    /// The bar fill: empty while muted, like the system indicator.
    var displayLevel: Double {
        isMuted ? 0 : value
    }

    var symbolName: String {
        HUDSymbol.name(kind: kind, level: value, isMuted: isMuted)
    }

    func isActive(at date: Date) -> Bool {
        date < expiresAt
    }
}

enum HUDSymbol {
    static func name(kind: HUDKind, level: Double, isMuted: Bool) -> String {
        switch kind {
        case .volume: volume(level: level, isMuted: isMuted)
        case .brightness: brightness(level: level)
        }
    }

    static func volume(level: Double, isMuted: Bool) -> String {
        if isMuted || level <= 0 { return "speaker.slash.fill" }
        if level < 0.34 { return "speaker.wave.1.fill" }
        if level < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    static func brightness(level: Double) -> String {
        level < 0.5 ? "sun.min.fill" : "sun.max.fill"
    }
}

/// A system level the HUD follows. Sources only report changes caused after `start()`.
@MainActor
protocol HUDLevelSource: AnyObject {
    var onLevel: ((HUDLevelReading) -> Void)? { get set }
    func start()
    func stop()
}

/// Shows the output volume and built-in display brightness in the island for a moment after
/// they change.
///
/// Volume comes from a CoreAudio property listener on the default output device
/// (`SystemVolumeSource`); brightness has no public change notification, so
/// `BuiltInBrightnessSource` watches the brightness keys and then reads the built-in display.
/// The level shows as a short-lived idle live activity in the wings
/// (`LiveActivityKind.hud`, `IdleHUDView`), or as `HUDOverlayView` while the island is expanded.
/// When the setting is off no listener or event monitor is installed. The macOS indicator
/// still appears: hiding it would mean consuming the media keys with an event tap.
@MainActor
final class HUDManager {
    /// How long the level stays in the notch after the last change.
    static let visibleDuration: TimeInterval = 1.5

    var onHUDChange: ((HUDOverlayState?) -> Void)?
    private(set) var state: HUDOverlayState?
    private(set) var isEnabled = false

    private var sources: [any HUDLevelSource] = []
    private let makeSources: @MainActor () -> [any HUDLevelSource]
    private let now: () -> Date
    private var hideTask: Task<Void, Never>?

    init(
        makeSources: @escaping @MainActor () -> [any HUDLevelSource] = HUDManager.systemSources,
        now: @escaping () -> Date = Date.init
    ) {
        self.makeSources = makeSources
        self.now = now
    }

    static func systemSources() -> [any HUDLevelSource] {
        [SystemVolumeSource(), BuiltInBrightnessSource()]
    }

    /// True while listeners / event monitors are installed.
    var isListening: Bool {
        !sources.isEmpty
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            startSources()
        } else {
            stopSources()
            hide()
        }
    }

    func show(_ reading: HUDLevelReading) {
        guard isEnabled else { return }
        hideTask?.cancel()
        let newState = HUDOverlayState(reading: reading, expiresAt: now().addingTimeInterval(Self.visibleDuration))
        state = newState
        onHUDChange?(newState)
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.visibleDuration))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    private func hide() {
        hideTask?.cancel()
        hideTask = nil
        guard state != nil else { return }
        state = nil
        onHUDChange?(nil)
    }

    private func startSources() {
        sources = makeSources()
        for source in sources {
            source.onLevel = { [weak self] reading in
                self?.show(reading)
            }
            source.start()
        }
    }

    private func stopSources() {
        for source in sources {
            source.stop()
            source.onLevel = nil
        }
        sources.removeAll()
    }
}
