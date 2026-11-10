import Foundation
import os

enum NotchFlowLog {
    static let subsystem = NotchFlowConstants.bundleID

    static let api = Logger(subsystem: subsystem, category: "API")
    static let media = Logger(subsystem: subsystem, category: "Media")
    static let license = Logger(subsystem: subsystem, category: "License")
    static let storage = Logger(subsystem: subsystem, category: "Storage")
    static let hover = Logger(subsystem: subsystem, category: "Hover")
    static let agents = Logger(subsystem: subsystem, category: "Agents")
    static let notifications = Logger(subsystem: subsystem, category: "Notifications")
    static let camera = Logger(subsystem: subsystem, category: "Camera")
    static let calendar = Logger(subsystem: subsystem, category: "Calendar")

    /// Builds up to 1.0.44 appended call traces to a world-readable file in /tmp.
    /// Remove it if this user owns it (never follows a symlink: removes the link itself).
    static func removeLegacyCallTraceFile() {
        let path = "/tmp/notchflow-call-debug.log"
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let owner = attributes[.ownerAccountID] as? NSNumber,
              owner.uint32Value == getuid() else { return }
        try? FileManager.default.removeItem(atPath: path)
    }
}
