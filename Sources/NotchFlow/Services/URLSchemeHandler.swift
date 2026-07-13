import AppKit
import Foundation

enum URLSchemeHandler {
    @MainActor
    static func handle(url: URL, appState: AppState) {
        guard url.scheme == "notchflow" else { return }
        guard appState.settings.urlSchemeAutomationEnabled else { return }

        switch url.host {
        case "play-pause":
            appState.mediaMonitor.togglePlayPause()
        case "show-island":
            AppController.appDelegate?.showIsland()
        case "mirror-toggle":
            handleMirrorToggle(appState: appState)
        case "add-note":
            if let text = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "text" })?
                .value {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.count <= 2_000 else { return }
                do {
                    try appState.notesManager.append(text: trimmed, isPremium: appState.isPremium)
                    appState.notes = appState.notesManager.notes
                } catch {
                    NotchFlowLog.api.error("Failed to append note from URL scheme: \(error.localizedDescription, privacy: .public)")
                }
            }
        default:
            break
        }
    }

    @MainActor
    private static func handleMirrorToggle(appState: AppState) {
        Task {
            await MirrorActivation.confirmAndToggle(in: appState)
        }
    }
}
