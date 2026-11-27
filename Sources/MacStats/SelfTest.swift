import AppKit
import StatsCore

/// UI layer: a smoke test for CI. Run the app with `MACSTATS_SELFTEST=<report file>`.
/// It opens real panels the same way a click does, checks that each one is visible, big enough and on
/// a screen, writes a report and quits (exit code 0 = pass, 1 = fail).
/// Timeline (seconds after launch): 3 open CPU menu · 4 open Network side menu · 5 open Interfaces
/// breakdown · hold for a screenshot · 10.5 open the overview (⌥-click Memory) · 12.5 open Settings by URL · 13.5 quit.
@MainActor
final class SelfTest {
    static var reportPath: String? { ProcessInfo.processInfo.environment["MACSTATS_SELFTEST"] }

    private let panels: PanelController
    private let statusBar: StatusBarController
    private let reportPath: String
    private var lines: [String] = []
    private var failures = 0

    init(panels: PanelController, statusBar: StatusBarController, reportPath: String) {
        self.panels = panels
        self.statusBar = statusBar
        self.reportPath = reportPath
    }

    func run() {
        log("screens: " + NSScreen.screens.map { NSStringFromRect($0.frame) }.joined(separator: ", "))
        step(3) { self.open("cpu", alt: false) }
        step(4) {
            self.check(level: 0, "CPU item menu")
            self.panels.select(level: 0, rowID: "sum:net", target: .itemMenu(itemID: "net", withOthers: false, back: false),
                               rowFrame: CGRect(x: 0, y: 420, width: 310, height: 26))
        }
        step(5) {
            self.check(level: 1, "Network side menu")
            self.panels.select(level: 1, rowID: "row:ifs", target: .breakdown(itemID: "net", kind: .interfaces),
                               rowFrame: CGRect(x: 0, y: 260, width: 310, height: 23))
        }
        step(6) { self.check(level: 2, "Interfaces breakdown") }
        step(10.5) {
            self.panels.close()
            self.open("mem", alt: true)
        }
        step(11.5) { self.check(level: 0, "Overview (⌥-click)") }
        step(12.5) {
            // A duplicate launch (started by CI) may already have opened Settings; close it to test the URL path.
            for w in NSApp.windows where w.title == "Mac Stats Settings" { w.orderOut(nil) }
            (NSApp.delegate as? AppDelegate)?.application(NSApp, open: [URL(string: "macstats://settings")!])
        }
        step(13) {
            let shown = NSApp.windows.contains { $0.title == "Mac Stats Settings" && $0.isVisible }
            self.log("\(shown ? "PASS" : "FAIL") Settings opened by macstats://settings")
            if !shown { self.failures += 1 }
        }
        step(13.5) {
            self.panels.close()
            self.finish()
        }
    }

    private func step(_ seconds: Double, _ action: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            MainActor.assumeIsolated { action() }
        }
    }

    private func open(_ id: String, alt: Bool) {
        guard let button = statusBar.button(for: id) else {
            fail("no menu bar button for \(id)")
            return
        }
        let windowFrame = button.window.map { NSStringFromRect($0.frame) } ?? "none"
        log("click \(id)\(alt ? " with ⌥" : ""): button window \(windowFrame)")
        panels.toggle(itemID: id, button: button, alt: alt)
    }

    private func check(level: Int, _ name: String) {
        let frame = panels.frame(level: level)
        let visible = panels.isVisible(level: level)
        let onScreen = NSScreen.screens.contains { $0.frame.intersects(frame) }
        // 100 pt wide and 50 pt tall: a breakdown with one row is legitimately short.
        let ok = visible && frame.width >= 100 && frame.height >= 50 && onScreen
        log("\(ok ? "PASS" : "FAIL") \(name): visible=\(visible) onScreen=\(onScreen) frame=\(NSStringFromRect(frame))")
        if !ok { failures += 1 }
    }

    private func fail(_ message: String) {
        failures += 1
        log("FAIL " + message)
    }

    private func log(_ line: String) {
        lines.append(line)
        print("SELFTEST " + line)
    }

    private func finish() {
        log(failures == 0 ? "RESULT pass" : "RESULT fail (\(failures))")
        try? lines.joined(separator: "\n").write(toFile: reportPath, atomically: true, encoding: .utf8)
        fflush(stdout)
        exit(failures == 0 ? 0 : 1)
    }
}
