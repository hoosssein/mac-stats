import AppKit
import os
import StatsCore

/// UI layer: one `NSStatusItem` per menu bar item, plus the Mac Stats icon when needed
/// (docs/kb/product-spec.md section 2).
@MainActor
final class StatusBarController: NSObject {
    private let model: AppModel
    private var items: [String: NSStatusItem] = [:]
    private var order: [String] = []
    private var appearanceObservation: NSKeyValueObservation?
    /// Called when an item is clicked: item id ("all" for the Mac Stats icon), its button, and whether ⌥ was held.
    var onClick: ((String, NSStatusBarButton, Bool) -> Void)?

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    /// The ids shown in the menu bar, left to right.
    private var wantedIDs: [String] {
        var ids: [String] = []
        if model.config.statsIconVisible { ids.append("all") }
        ids += model.config.barItems.map(\.id)
        return ids
    }

    /// Creates, removes or reorders status items to match the config.
    func rebuild() {
        let wanted = wantedIDs
        guard wanted != order else { redraw(); return }
        for (_, item) in items { NSStatusBar.system.removeStatusItem(item) }
        items.removeAll()
        // New status items appear to the left of existing ones, so create them right to left.
        for id in wanted.reversed() {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = item.button {
                button.target = self
                button.action = #selector(clicked(_:))
                button.sendAction(on: [.leftMouseDown, .rightMouseDown])
                button.identifier = NSUserInterfaceItemIdentifier(id)
                button.imagePosition = .imageOnly
                button.setAccessibilityLabel(id == "all" ? "Mac Stats" : model.config.item(id: id)?.name)
            }
            items[id] = item
        }
        order = wanted
        Log.menuBar.notice("menu bar items: \(wanted.joined(separator: ", "), privacy: .public)")
        // Redraw at once when the menu bar switches between light and dark.
        appearanceObservation = items.values.first?.button?.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.redraw(force: true) }
        }
        redraw(force: true)
    }

    /// Redraws every item (once per second, after each sampling round).
    func redraw(force: Bool = false) {
        if model.screenLocked && model.config.general.whenLocked == .pauseDrawing && !force { return }
        let monochrome = model.config.general.menuBarChartColor == .monochrome
        for (id, status) in items {
            guard let button = status.button else { continue }
            if id == "all" {
                if force || button.image == nil {
                    let icon = MenuBarRenderer.statsIcon()
                    button.image = icon
                    status.length = ceil(icon.size.width)
                }
                continue
            }
            guard let item = model.config.item(id: id) else { continue }
            let image = MenuBarRenderer.image(item: item, presenter: model.presenter(item),
                                              spark: model.spark(item), monochrome: monochrome)
            button.image = image
            // Exactly as wide as the drawing: no extra padding inside the status item.
            let width = ceil(image.size.width)
            if status.length != width { status.length = width }
        }
    }

    func button(for id: String) -> NSStatusBarButton? { items[id]?.button }

    func isStatusButtonWindow(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        return items.values.contains { $0.button?.window === window }
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        guard let id = sender.identifier?.rawValue else { return }
        let alt = NSApp.currentEvent?.modifierFlags.contains(.option) ?? false
        let frame = sender.window?.frame.logText ?? "no window"
        Log.menuBar.notice("click \(id, privacy: .public) option=\(alt) button window \(frame, privacy: .public)")
        onClick?(id, sender, alt)
    }

    func highlight(_ id: String?) {
        for (key, item) in items { item.button?.highlight(key == id) }
    }
}
