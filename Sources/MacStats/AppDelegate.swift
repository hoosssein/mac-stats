import AppKit
import os
import StatsCore

/// UI layer: wires the model, the menu bar, the panels and the settings window together.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private lazy var statusBar = StatusBarController(model: model)
    private lazy var panels = PanelController(model: model)
    private lazy var settings = SettingsWindowController(model: model)
    private var observers: [NSObjectProtocol] = []
    private var selfTest: SelfTest?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let screens = NSScreen.screens.map { $0.frame.logText }.joined(separator: "; ")
        Log.app.notice("Mac Stats \(version, privacy: .public) started on macOS \(osVersion, privacy: .public); screens: \(screens, privacy: .public)")
        statusBar.onClick = { [weak self] id, button, alt in
            self?.panels.toggle(itemID: id, button: button, alt: alt)
        }
        panels.statusBar = statusBar
        panels.openSettings = { [weak self] id in self?.settings.show(itemID: id) }
        model.onConfigChange = { [weak self] old, new in self?.configChanged(old, new) }
        model.onTick = { [weak self] in self?.statusBar.redraw() }

        statusBar.rebuild()
        model.start()
        if let path = SelfTest.reportPath {
            selfTest = SelfTest(panels: panels, statusBar: statusBar, reportPath: path)
            selfTest?.run()
        }

        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(forName: SingleInstance.showSettings, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                Log.app.notice("a second launch asked for Settings")
                self?.settings.show(itemID: nil)
            }
        })
        observers.append(center.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.screenLocked = true }
        })
        observers.append(center.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.screenLocked = false
                self?.statusBar.redraw(force: true)
            }
        })
    }

    /// Opening the app again while it runs (Finder, Spotlight, Launchpad) opens Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Log.app.notice("reopened: show settings")
        settings.show(itemID: nil)
        return false
    }

    /// `macstats://settings` opens Settings; `macstats://settings/<item id>` selects that item.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "macstats" {
            Log.app.notice("open url \(url.host ?? "", privacy: .public)")
            if url.host == "settings" {
                let itemID = url.pathComponents.count > 1 ? url.pathComponents[1] : nil
                settings.show(itemID: itemID.flatMap { model.config.item(id: $0) != nil ? $0 : nil })
            }
        }
    }

    private func configChanged(_ old: AppConfig, _ new: AppConfig) {
        // Text widths are remembered to stop jitter; forget them when what an item draws changes.
        for item in new.items {
            if let before = old.item(id: item.id),
               before.displayMode != item.displayMode || before.showLabel != item.showLabel || before.valueShown != item.valueShown {
                MenuBarRenderer.resetWidths(for: item.id)
            }
        }
        if old.general.units != new.general.units {
            for item in new.items { MenuBarRenderer.resetWidths(for: item.id) }
        }
        if old.general.appearance != new.general.appearance {
            panels.applyAppearance()
            settings.applyAppearance()
        }
        statusBar.rebuild()
        // Close the panels if their menu bar item is gone.
        if let anchor = panels.anchorID {
            let stillThere = anchor == "all" ? new.statsIconVisible : new.item(id: anchor)?.showInMenuBar == true
            if !stillThere { panels.close() }
        }
    }
}
