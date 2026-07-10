import AppKit
import Carbon.HIToolbox
import Foundation

enum MediaTransportCommand: Sendable {
    case playPause
    case next
    case previous
}

enum MediaPlayerController {
    static func perform(_ command: MediaTransportCommand, playerBundleID: String?) {
        switch resolvedPlayer(from: playerBundleID) {
        case "com.spotify.client":
            spotify(command)
        case "com.apple.Music", "com.apple.iTunes":
            music(command)
        default:
            SystemMediaKeyPoster.post(command)
        }
    }

    private static func resolvedPlayer(from bundleID: String?) -> String? {
        if let bundleID, !bundleID.isEmpty { return bundleID }
        if isRunning("com.spotify.client") { return "com.spotify.client" }
        if isRunning("com.apple.Music") { return "com.apple.Music" }
        if isRunning("com.apple.iTunes") { return "com.apple.iTunes" }
        return nil
    }

    private static func isRunning(_ bundleID: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }

    private static func spotify(_ command: MediaTransportCommand) {
        let verb: String
        switch command {
        case .playPause: verb = "playpause"
        case .next: verb = "next track"
        case .previous: verb = "previous track"
        }
        runScript("tell application \"Spotify\" to \(verb)")
    }

    private static func music(_ command: MediaTransportCommand) {
        let verb: String
        switch command {
        case .playPause: verb = "playpause"
        case .next: verb = "next track"
        case .previous: verb = "previous track"
        }
        runScript("tell application \"Music\" to \(verb)")
    }

    static func seek(to position: Double, playerBundleID: String?) {
        let seconds = Int(position)
        switch resolvedPlayer(from: playerBundleID) {
        case "com.spotify.client":
            runScript("tell application \"Spotify\" to set player position to \(seconds)")
        case "com.apple.Music", "com.apple.iTunes":
            runScript("tell application \"Music\" to set player position to \(seconds)")
        default:
            break
        }
    }

    private static func runScript(_ source: String) {
        guard let script = NSAppleScript(source: source) else { return }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
    }
}

private enum SystemMediaKeyPoster {
    static func post(_ command: MediaTransportCommand) {
        let keyType: Int32
        switch command {
        case .playPause: keyType = NX_KEYTYPE_PLAY
        case .next: keyType = NX_KEYTYPE_NEXT
        case .previous: keyType = NX_KEYTYPE_PREVIOUS
        }
        postKey(keyType, keyDown: true)
        postKey(keyType, keyDown: false)
    }

    private static func postKey(_ key: Int32, keyDown: Bool) {
        let data1 = Int((key << 16) | ((keyDown ? 0xA : 0xB) << 8))
        let flags = NSEvent.ModifierFlags(rawValue: keyDown ? 0xA00 : 0xB00)
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        ) else { return }
        event.cgEvent?.post(tap: .cgSessionEventTap)
    }
}
