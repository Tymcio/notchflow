import AppKit
import Foundation

enum MirrorActivation {
    @MainActor
    static func confirmAndToggle(in appState: AppState) async {
        if appState.cameraMirrorManager.isActive {
            appState.cameraMirrorManager.stopPreview()
            return
        }

        guard confirmStart() else { return }
        await appState.cameraMirrorManager.startPreview()
    }

    @MainActor
    static func confirmStart() -> Bool {
        let alert = NSAlert()
        alert.messageText = loc("Enable camera preview?")
        alert.informativeText = loc("NotchFlow will request camera access. Continue?")
        alert.alertStyle = .warning
        alert.addButton(withTitle: loc("Enable"))
        alert.addButton(withTitle: loc("Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }
}
