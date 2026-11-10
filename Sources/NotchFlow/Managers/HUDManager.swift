import AppKit
import Foundation

enum HUDKind: String, Sendable {
    case volume
    case brightness
}

struct HUDOverlayState: Equatable, Sendable {
    let kind: HUDKind
    let value: Double
    let label: String
    let expiresAt: Date
}

@MainActor
final class HUDManager {
    var onHUDChange: ((HUDOverlayState?) -> Void)?

    private var observers: [NSObjectProtocol] = []
    private var hideTask: Task<Void, Never>?

    /// Registers once; the manager lives for the whole app session.
    func start() {
        guard observers.isEmpty else { return }
        registerObservers()
    }

    private func registerObservers() {
        let names = [
            "com.apple.sound.beep.sound",
            "AppleBrightnessChanged",
            "NSSystemVolumeDidChangeNotification"
        ]

        for name in names {
            let token = NotificationCenter.default.addObserver(
                forName: Notification.Name(name),
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let level = HUDLevel(userInfo: notification.userInfo)
                MainActor.assumeIsolated {
                    self?.handle(level, name: name)
                }
            }
            observers.append(token)
        }
    }

    /// Levels read from the notification on the posting thread (only Sendable values cross over).
    private struct HUDLevel: Sendable {
        let volume: Double?
        let brightness: Double?

        init(userInfo: [AnyHashable: Any]?) {
            volume = (userInfo?["Volume"] as? Double) ?? (userInfo?["VolumeScalar"] as? Double)
            brightness = userInfo?["Brightness"] as? Double
        }
    }

    private func handle(_ level: HUDLevel, name: String) {
        if name.contains("Volume") || name.contains("sound") {
            showHUD(kind: .volume, value: level.volume ?? 0.5, label: loc("Volume"))
            return
        }

        if name.contains("Brightness") {
            showHUD(kind: .brightness, value: level.brightness ?? 0.5, label: loc("Brightness"))
        }
    }

    private func showHUD(kind: HUDKind, value: Double, label: String) {
        hideTask?.cancel()
        let state = HUDOverlayState(
            kind: kind,
            value: min(max(value, 0), 1),
            label: label,
            expiresAt: Date().addingTimeInterval(1.2)
        )
        onHUDChange?(state)

        hideTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            await MainActor.run {
                self.onHUDChange?(nil)
            }
        }
    }
}
