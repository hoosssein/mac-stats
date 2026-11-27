import AppKit
import StatsCore

/// UI layer: wires the model, the menu bar, the panels and the settings window together.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private lazy var statusBar = StatusBarController(model: model)
    private lazy var panels = PanelController(model: model)
    private lazy var settings = SettingsWindowController(model: model)
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar.onClick = { [weak self] id, button, alt in
            self?.panels.toggle(itemID: id, button: button, alt: alt)
        }
        panels.statusBar = statusBar
        panels.openSettings = { [weak self] id in self?.settings.show(itemID: id) }
        model.onConfigChange = { [weak self] old, new in self?.configChanged(old, new) }
        model.onTick = { [weak self] in self?.statusBar.redraw() }

        statusBar.rebuild()
        model.start()

        let center = DistributedNotificationCenter.default()
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
