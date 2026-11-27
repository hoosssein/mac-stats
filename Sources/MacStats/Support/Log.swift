import Foundation
import os

/// UI layer: app logging through Apple's unified logging system.
/// Collect the last 30 minutes with:
///   log show --last 30m --info --predicate 'subsystem == "app.macstats.MacStats"'
/// Log lines contain only app internals (item ids, panel kinds, sizes, counts), never process names or file paths.
enum Log {
    static let subsystem = "app.macstats.MacStats"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let menuBar = Logger(subsystem: subsystem, category: "menubar")
    static let panels = Logger(subsystem: subsystem, category: "panels")
    static let history = Logger(subsystem: subsystem, category: "history")
    static let sampling = Logger(subsystem: subsystem, category: "sampling")
}

extension CGRect {
    /// Short text for logs: "x,y wxh".
    var logText: String { "\(Int(minX)),\(Int(minY)) \(Int(width))x\(Int(height))" }
}
