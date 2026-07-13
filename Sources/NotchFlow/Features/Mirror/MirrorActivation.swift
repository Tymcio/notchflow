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
        alert.messageText = "Włączyć podgląd kamery?"
        alert.informativeText = "NotchFlow poprosi o dostęp do kamery. Kontynuować?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Włącz")
        alert.addButton(withTitle: "Anuluj")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
