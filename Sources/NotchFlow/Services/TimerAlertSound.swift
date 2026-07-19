import AppKit
import Foundation

/// Timer completion tones — Clock-app ringtones from ToneLibrary, plus short system alerts.
enum TimerAlertSound {
    static let none = ""
    /// Default matches the classic iPhone / Clock timer tone.
    static let defaultID = "ringtone/Radar"

    private static let systemSoundsDirectory = URL(fileURLWithPath: "/System/Library/Sounds", isDirectory: true)
    private static let toneLibraryRoot = URL(
        fileURLWithPath: "/System/Library/PrivateFrameworks/ToneLibrary.framework/Versions/A/Resources",
        isDirectory: true
    )
    private static let ringtonesDirectory = toneLibraryRoot.appendingPathComponent("Ringtones", isDirectory: true)

    /// Retained so `NSSound.play()` is not deallocated mid-playback.
    @MainActor
    private static var playingSound: NSSound?

    struct Option: Identifiable, Hashable {
        let id: String
        let title: String
    }

    static var ringtoneOptions: [Option] {
        soundOptions(in: ringtonesDirectory, idPrefix: "ringtone", extensions: ["m4r", "caf", "aiff", "m4a"])
    }

    static var systemOptions: [Option] {
        soundOptions(in: systemSoundsDirectory, idPrefix: "system", extensions: ["aiff", "wav", "caf"])
    }

    static func isValid(_ id: String) -> Bool {
        if id == none { return true }
        return url(for: id) != nil
    }

    /// Migrates legacy bare names (e.g. `"Glass"`) to prefixed IDs.
    static func migratedID(_ saved: String) -> String {
        if saved.isEmpty { return none }
        if isValid(saved) { return saved }
        let legacySystem = "system/\(saved)"
        if isValid(legacySystem) { return legacySystem }
        return defaultID
    }

    @MainActor
    static func play(_ id: String, loops: Bool = false) {
        stop()
        guard let url = url(for: id) else { return }
        guard let sound = NSSound(contentsOf: url, byReference: true) else { return }
        sound.loops = loops
        playingSound = sound
        sound.play()
    }

    @MainActor
    static func stop() {
        playingSound?.stop()
        playingSound = nil
    }

    // MARK: - Private

    private static func url(for id: String) -> URL? {
        guard !id.isEmpty else { return nil }
        let parts = id.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let kind = parts[0]
        let name = parts[1]

        switch kind {
        case "ringtone":
            return existingFile(named: name, in: ringtonesDirectory, extensions: ["m4r", "caf", "aiff", "m4a"])
        case "system":
            return existingFile(named: name, in: systemSoundsDirectory, extensions: ["aiff", "wav", "caf"])
        default:
            return nil
        }
    }

    private static func existingFile(named name: String, in directory: URL, extensions: [String]) -> URL? {
        for ext in extensions {
            let url = directory.appendingPathComponent(name).appendingPathExtension(ext)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    private static func soundOptions(in directory: URL, idPrefix: String, extensions: [String]) -> [Option] {
        let extSet = Set(extensions.map { $0.lowercased() })
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            .filter { extSet.contains($0.pathExtension.lowercased()) }
            .map { url -> Option in
                let title = url.deletingPathExtension().lastPathComponent
                return Option(id: "\(idPrefix)/\(title)", title: displayTitle(for: title))
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private static func displayTitle(for filename: String) -> String {
        filename
            .replacingOccurrences(of: "-EncoreInfinitum", with: "")
            .replacingOccurrences(of: "-EncoreRemix", with: "")
    }
}
