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

/// Shows a short volume / brightness overlay in the island.
///
/// Nothing drives it yet. It used to observe `com.apple.sound.beep.sound`,
/// `AppleBrightnessChanged` and `NSSystemVolumeDidChangeNotification` on the in-process
/// `NotificationCenter`, where macOS never posts them (the first is a defaults key, the others
/// are not system notifications at all), so the overlay never appeared. A working source would
/// be a CoreAudio listener on the default output device's volume (as `OutputMuteMonitor` does);
/// brightness has no public change notification. Wiring one up also needs the panel to be
/// presented and sized for the overlay, which the 32 pt idle island cannot hold.
@MainActor
final class HUDManager {
    var onHUDChange: ((HUDOverlayState?) -> Void)?

    private var hideTask: Task<Void, Never>?

    func showHUD(kind: HUDKind, value: Double, label: String) {
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
