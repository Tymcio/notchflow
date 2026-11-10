import AppKit
import CoreGraphics
import Foundation

/// A media / special key from an `NSEvent` of type `.systemDefined` (subtype 8, `NX_SUBTYPE_AUX_CONTROL_BUTTONS`).
struct SystemDefinedKeyEvent: Equatable, Sendable {
    static let auxControlButtonsSubtype: Int16 = 8
    /// `NX_KEYTYPE_BRIGHTNESS_UP`
    static let brightnessUpKeyCode = 2
    /// `NX_KEYTYPE_BRIGHTNESS_DOWN`
    static let brightnessDownKeyCode = 3

    let keyCode: Int
    let isKeyDown: Bool
    let isRepeat: Bool

    /// `data1` packs the key code in bits 16–31, the key state in bits 8–15 (0x0A down,
    /// 0x0B up) and the repeat flag in bit 0.
    init?(subtype: Int16, data1: Int) {
        guard subtype == Self.auxControlButtonsSubtype else { return nil }
        keyCode = (data1 & 0xFFFF_0000) >> 16
        isKeyDown = (data1 & 0xFF00) >> 8 == 0x0A
        isRepeat = data1 & 0x1 != 0
    }

    var isBrightnessKeyDown: Bool {
        isKeyDown && (keyCode == Self.brightnessUpKeyCode || keyCode == Self.brightnessDownKeyCode)
    }
}

/// Reads the brightness of the active built-in display through the private DisplayServices
/// framework (no public API exists). Only `DisplayServicesGetBrightness` is ever called; the
/// brightness is never set. Returns `nil` without a lit built-in display or when the framework
/// or symbol is missing.
@MainActor
final class BuiltInBrightnessReader {
    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32

    private static let frameworkPath = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"

    private var getBrightness: GetBrightness?
    private var didLoad = false
    private var didLogFailure = false

    func read() -> Double? {
        guard let display = Self.activeBuiltInDisplay(), let getBrightness = loadFunction() else { return nil }
        var value: Float = 0
        let status = getBrightness(display, &value)
        guard status == 0 else {
            logFailureOnce("DisplayServicesGetBrightness returned \(status)")
            return nil
        }
        return Double(min(max(value, 0), 1))
    }

    private func loadFunction() -> GetBrightness? {
        if didLoad { return getBrightness }
        didLoad = true
        // The handle stays open for the life of the app; dlclose would invalidate the symbol.
        guard let handle = dlopen(Self.frameworkPath, RTLD_LAZY) else {
            logFailureOnce("DisplayServices framework unavailable")
            return nil
        }
        guard let symbol = dlsym(handle, "DisplayServicesGetBrightness") else {
            logFailureOnce("DisplayServicesGetBrightness unavailable")
            return nil
        }
        getBrightness = unsafeBitCast(symbol, to: GetBrightness.self)
        return getBrightness
    }

    private func logFailureOnce(_ message: String) {
        guard !didLogFailure else { return }
        didLogFailure = true
        NotchFlowLog.hud.notice("Brightness HUD disabled: \(message, privacy: .public)")
    }

    /// The built-in panel when it is on and awake (not a closed lid / clamshell).
    private static func activeBuiltInDisplay() -> CGDirectDisplayID? {
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(UInt32(displays.count), &displays, &count) == .success else { return nil }
        return displays.prefix(Int(count)).first { display in
            CGDisplayIsBuiltin(display) != 0 && CGDisplayIsAsleep(display) == 0
        }
    }
}

/// Reports built-in display brightness after the brightness keys are pressed. There is no
/// public change notification, so it watches `.systemDefined` key events (a global monitor,
/// which needs Accessibility, plus a local one) and reads the level 60 ms after a press — once
/// per burst, so held keys update continuously — and again when the keys settle.
@MainActor
final class BuiltInBrightnessSource: HUDLevelSource {
    var onLevel: ((HUDLevelReading) -> Void)?

    private static let firstReadDelay: Duration = .milliseconds(60)
    private static let settleReadDelay: Duration = .milliseconds(350)

    private let reader = BuiltInBrightnessReader()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var quickReadTask: Task<Void, Never>?
    private var settleReadTask: Task<Void, Never>?

    func start() {
        guard globalMonitor == nil, localMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            self?.handle(subtype: event.subtype.rawValue, data1: event.data1)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            self?.handle(subtype: event.subtype.rawValue, data1: event.data1)
            return event
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
        quickReadTask?.cancel()
        quickReadTask = nil
        settleReadTask?.cancel()
        settleReadTask = nil
    }

    private func handle(subtype: Int16, data1: Int) {
        guard let key = SystemDefinedKeyEvent(subtype: subtype, data1: data1), key.isBrightnessKeyDown else { return }
        scheduleReads()
    }

    private func scheduleReads() {
        if quickReadTask == nil {
            quickReadTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.firstReadDelay)
                guard !Task.isCancelled else { return }
                self?.quickReadTask = nil
                self?.report()
            }
        }
        settleReadTask?.cancel()
        settleReadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.settleReadDelay)
            guard !Task.isCancelled else { return }
            self?.settleReadTask = nil
            self?.report()
        }
    }

    private func report() {
        guard let level = reader.read() else { return }
        onLevel?(HUDLevelReading(kind: .brightness, level: level))
    }
}
