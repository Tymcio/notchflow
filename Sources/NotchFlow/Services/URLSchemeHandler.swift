import AppKit
import Foundation

enum URLSchemeHandler {
    @MainActor
    static func handle(url: URL, appState: AppState) {
        guard url.scheme == "notchflow" else { return }

        switch url.host {
        case "play-pause":
            appState.mediaMonitor.togglePlayPause()
        case "show-island":
            AppController.appDelegate?.showIsland()
        case "mirror-toggle":
            Task {
                if appState.cameraMirrorManager.isActive {
                    appState.cameraMirrorManager.stopPreview()
                } else {
                    await appState.cameraMirrorManager.startPreview()
                }
            }
        case "add-note":
            if let text = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "text" })?
                .value {
                try? appState.notesManager.append(text: text, isPremium: appState.isPremium)
                appState.notes = appState.notesManager.notes
            }
        default:
            break
        }
    }
}
