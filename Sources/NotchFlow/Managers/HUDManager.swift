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

    func start() {
        registerObservers()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
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
                self?.handle(notification: notification, name: name)
            }
            observers.append(token)
        }
    }

    private func handle(notification: Notification, name: String) {
        let userInfo = notification.userInfo ?? [:]

        if name.contains("Volume") || name.contains("sound") {
            let volume = (userInfo["Volume"] as? Double)
                ?? (userInfo["VolumeScalar"] as? Double)
                ?? Double(NSApplication.shared.windows.count > 0 ? 0.5 : 0.5)
            showHUD(kind: .volume, value: volume, label: "Głośność")
            return
        }

        if name.contains("Brightness") {
            let brightness = (userInfo["Brightness"] as? Double) ?? 0.5
            showHUD(kind: .brightness, value: brightness, label: "Jasność")
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
