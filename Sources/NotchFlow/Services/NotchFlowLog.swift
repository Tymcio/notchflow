import Foundation
import os

enum NotchFlowLog {
    static let subsystem = NotchFlowConstants.bundleID

    static let api = Logger(subsystem: subsystem, category: "API")
    static let media = Logger(subsystem: subsystem, category: "Media")
    static let license = Logger(subsystem: subsystem, category: "License")
    static let storage = Logger(subsystem: subsystem, category: "Storage")
    static let hover = Logger(subsystem: subsystem, category: "Hover")
}
