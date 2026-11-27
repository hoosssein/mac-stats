import AppKit
import os

/// UI layer: only one Mac Stats runs at a time (docs/kb/product-spec.md section 11).
/// A second launch, even of another copy of the app, asks the running one to show Settings and quits.
enum SingleInstance {
    /// Sent by a second launch to the running instance.
    static let showSettings = Notification.Name("app.macstats.MacStats.showSettings")

    /// Another running Mac Stats that started before this one. If two start at the same moment,
    /// the one with the lower process id wins, so exactly one survives.
    static func olderInstance() -> NSRunningApplication? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
        let me = NSRunningApplication.current
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first { other in
            guard other.processIdentifier != me.processIdentifier, !other.isTerminated else { return false }
            if let a = other.launchDate, let b = me.launchDate, a != b { return a < b }
            return other.processIdentifier < me.processIdentifier
        }
    }

    /// Quits this process if another instance is already running, after asking it to show Settings.
    static func quitIfAlreadyRunning() {
        guard let existing = olderInstance() else { return }
        Log.app.notice("another instance is running (pid \(existing.processIdentifier)); showing its Settings and quitting")
        DistributedNotificationCenter.default().postNotificationName(showSettings, object: nil, userInfo: nil,
                                                                     deliverImmediately: true)
        exit(0)
    }
}
