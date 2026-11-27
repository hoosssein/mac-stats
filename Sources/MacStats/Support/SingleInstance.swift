import AppKit
import Darwin
import os
import StatsCore

/// UI layer: only one Mac Stats runs at a time (docs/kb/product-spec.md section 11).
/// The running instance holds an exclusive lock on `instance.lock` in the support folder. A second launch, even of
/// another copy of the app or of the bare binary, cannot take the lock: it asks the running one to show Settings and
/// quits. The system releases the lock when the process ends, even after a crash.
enum SingleInstance {
    /// Sent by a second launch to the running instance.
    static let showSettings = Notification.Name("app.macstats.MacStats.showSettings")

    /// Kept open for the life of the process; closing it would release the lock.
    nonisolated(unsafe) private static var lockFD: Int32 = -1

    static var lockURL: URL { ConfigStore.supportDirectory.appendingPathComponent("instance.lock") }

    /// True when this process now holds the lock (or the lock cannot be used at all, so the app still runs).
    static func acquire() -> Bool {
        try? FileManager.default.createDirectory(at: ConfigStore.supportDirectory, withIntermediateDirectories: true)
        let fd = open(lockURL.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else {
            Log.app.error("cannot open the instance lock file; running without the single-instance check")
            return true
        }
        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            lockFD = fd
            return true
        }
        close(fd)
        return false
    }

    /// Quits this process if another instance is already running, after asking it to show Settings.
    static func quitIfAlreadyRunning() {
        if acquire() {
            Log.app.notice("instance lock acquired (pid \(getpid()))")
            return
        }
        Log.app.notice("another instance is running; asking it to show Settings and quitting (pid \(getpid()))")
        DistributedNotificationCenter.default().postNotificationName(showSettings, object: nil, userInfo: nil,
                                                                     deliverImmediately: true)
        exit(0)
    }
}
