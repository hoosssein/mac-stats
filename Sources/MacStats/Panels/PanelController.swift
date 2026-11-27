import AppKit
import Observation
import StatsCore
import SwiftUI

/// What a panel level shows.
enum PanelContent: Equatable {
    /// An item's menu. `withOthers` adds the Other metrics list; `back` adds "‹ All items".
    case itemMenu(itemID: String, withOthers: Bool, back: Bool)
    /// The All metrics list (Mac Stats icon in item-menu mode).
    case allMetrics
    case overview
    case breakdown(itemID: String, kind: BreakdownKind)

    var breakdownKind: BreakdownKind? {
        if case .breakdown(_, let k) = self { return k }
        return nil
    }
}

/// A borderless, non-activating panel that can still take key events (for Esc).
final class MenuPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// UI layer: owns the three panel levels (docs/kb/product-spec.md section 6):
/// placement (right, flip left, keep direction, overlap), hover intent and closing.
@MainActor
@Observable
final class PanelController {
    static let levels = 3

    private(set) var contents: [PanelContent?] = Array(repeating: nil, count: PanelController.levels)
    /// The highlighted row per level (the row whose side panel is open).
    private(set) var highlighted: [String?] = Array(repeating: nil, count: PanelController.levels)
    private(set) var anchorID: String?

    @ObservationIgnored private let model: AppModel
    @ObservationIgnored private var panels: [MenuPanel] = []
    @ObservationIgnored private var hosts: [NSHostingView<AnyView>?] = Array(repeating: nil, count: PanelController.levels)
    @ObservationIgnored private var directions: [Int] = Array(repeating: 1, count: PanelController.levels)
    @ObservationIgnored private var timers: [Timer?] = Array(repeating: nil, count: PanelController.levels)
    @ObservationIgnored private var pendingRow: [String?] = Array(repeating: nil, count: PanelController.levels)
    @ObservationIgnored private var anchorFrame: NSRect = .zero
    @ObservationIgnored private var monitors: [Any] = []
    @ObservationIgnored var statusBar: StatusBarController?
    @ObservationIgnored var openSettings: ((String?) -> Void)?

    init(model: AppModel) {
        self.model = model
        panels = (0..<PanelController.levels).map { _ in MenuPanel() }
    }

    var isOpen: Bool { contents[0] != nil }

    /// Applies the Appearance setting to the panels (menu bar items are not changed).
    func applyAppearance() {
        for p in panels { p.appearance = model.nsAppearance }
    }

    // MARK: Open and close

    /// Opens the panel for a menu bar item. Clicking the open item again closes it.
    func toggle(itemID: String, button: NSStatusBarButton, alt: Bool) {
        // A pending hover from the old panel must not open a side menu next to the new one.
        cancelPending(through: PanelController.levels - 1)
        if anchorID == itemID && isOpen { close(); return }
        guard let window = button.window else { return }
        anchorFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        anchorID = itemID
        let overview = (model.config.menu.clickOpens == .overview) != alt
        let content: PanelContent
        if overview {
            content = .overview
        } else if itemID == "all" {
            content = .allMetrics
        } else {
            content = .itemMenu(itemID: itemID, withOthers: true, back: false)
        }
        model.panelOpened()
        // Switching to another item closes the old side panels first.
        for i in 1..<PanelController.levels { closeLevel(i) }
        highlighted[0] = nil
        show(content, at: 0)
        statusBar?.highlight(itemID)
        installMonitors()
    }

    func close() {
        for i in 0..<PanelController.levels { closeLevel(i) }
        anchorID = nil
        statusBar?.highlight(nil)
        removeMonitors()
        model.setOpenBreakdowns([])
    }

    /// Replaces what level 0 shows (overview ⇄ item menu in place).
    func replaceRoot(_ content: PanelContent) {
        closeChildren(of: 0)
        show(content, at: 0)
    }

    private func closeLevel(_ i: Int) {
        timers[i]?.invalidate()
        timers[i] = nil
        pendingRow[i] = nil
        contents[i] = nil
        highlighted[i] = nil
        panels[i].orderOut(nil)
        hosts[i] = nil
        panels[i].contentView = nil
    }

    private func closeChildren(of level: Int) {
        for i in (level + 1)..<PanelController.levels { closeLevel(i) }
        highlighted[level] = nil
        syncBreakdowns()
    }

    private func syncBreakdowns() {
        model.setOpenBreakdowns(Set(contents.compactMap { $0?.breakdownKind }))
    }

    // MARK: Showing a level

    private func show(_ content: PanelContent, at level: Int) {
        contents[level] = content
        let root = AnyView(PanelRoot(level: level, content: content)
            .environment(model)
            .environment(self))
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        let effect = NSVisualEffectView()
        effect.material = .menu
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 10
        effect.layer?.masksToBounds = true
        host.translatesAutoresizingMaskIntoConstraints = true
        let size = host.fittingSize
        effect.frame = NSRect(origin: .zero, size: size)
        host.frame = effect.bounds
        host.autoresizingMask = [.width, .height]
        effect.addSubview(host)
        let panel = panels[level]
        panel.appearance = model.nsAppearance
        panel.contentView = effect
        hosts[level] = host
        panel.setContentSize(size)
        if level == 0 { placeRoot(size: size) }
        panel.orderFrontRegardless()
        if level == 0 { panel.makeKey() }
        syncBreakdowns()
    }

    /// Keeps the panel's top edge fixed when its content changes size.
    func contentSizeChanged(level: Int, size: CGSize) {
        guard contents[level] != nil else { return }
        let panel = panels[level]
        let old = panel.frame
        guard abs(old.width - size.width) > 0.5 || abs(old.height - size.height) > 0.5 else { return }
        var frame = NSRect(x: old.minX, y: old.maxY - size.height, width: size.width, height: size.height)
        if let screen = screenFrame(for: old), frame.minY < screen.minY { frame.origin.y = screen.minY }
        if level == 0 { frame.origin.x = rootX(width: size.width) }
        panel.setFrame(frame, display: true)
    }

    private func screenFrame(for rect: NSRect) -> NSRect? {
        (NSScreen.screens.first { $0.frame.intersects(rect) } ?? NSScreen.main)?.visibleFrame
    }

    private func rootX(width: CGFloat) -> CGFloat {
        let screen = screenFrame(for: anchorFrame) ?? .zero
        var x = anchorFrame.minX
        if x + width > screen.maxX - 4 { x = screen.maxX - 4 - width }
        return max(screen.minX + 4, x)
    }

    private func placeRoot(size: CGSize) {
        let y = anchorFrame.minY - 4 - size.height
        panels[0].setFrameOrigin(NSPoint(x: rootX(width: size.width), y: y))
    }

    /// Places a child panel next to its parent, top aligned with the row (frame in screen coordinates).
    private func place(level i: Int, rowTop: CGFloat) {
        let parent = panels[i - 1].frame
        let size = panels[i].frame.size
        let screen = screenFrame(for: parent) ?? parent
        let rightX = parent.maxX - 3, leftX = parent.minX - size.width + 3
        let fitsRight = rightX + size.width <= screen.maxX, fitsLeft = leftX >= screen.minX
        let preferred = i == 1 ? 1 : directions[i - 1]
        let dir = preferred == 1 ? (fitsRight ? 1 : fitsLeft ? -1 : 1) : (fitsLeft ? -1 : fitsRight ? 1 : -1)
        directions[i] = dir
        var x = dir == 1 ? rightX : leftX
        x = min(max(x, screen.minX), screen.maxX - size.width)
        var y = rowTop + 8 - size.height
        if y < screen.minY { y = screen.minY }
        if y + size.height > screen.maxY { y = screen.maxY - size.height }
        panels[i].setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: Rows

    /// Converts a frame in a level's SwiftUI global space to screen coordinates (top edge).
    private func screenTop(level: Int, rowFrame: CGRect) -> CGFloat {
        panels[level].frame.maxY - rowFrame.minY
    }

    /// A row was hovered. Opens its target after the hover-intent delay (60 ms, or 160 ms when a
    /// side panel is already open). A nil target closes the children instead.
    func hover(level: Int, rowID: String, target: PanelContent?, rowFrame: CGRect) {
        guard level + 1 < PanelController.levels || target == nil else { return }
        if highlighted[level] == rowID { cancelPending(through: level); return }
        if pendingRow[level] == rowID { return }
        timers[level]?.invalidate()
        pendingRow[level] = rowID
        let delay = contents[min(level + 1, PanelController.levels - 1)] != nil && level + 1 < PanelController.levels ? 0.16 : 0.06
        timers[level] = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.select(level: level, rowID: rowID, target: target, rowFrame: rowFrame)
            }
        }
    }

    /// Opens a row's target right away (click).
    func select(level: Int, rowID: String, target: PanelContent?, rowFrame: CGRect) {
        timers[level]?.invalidate()
        timers[level] = nil
        pendingRow[level] = nil
        guard contents[level] != nil else { return }
        let child = level + 1
        if let target, child < PanelController.levels, highlighted[level] == rowID, contents[child] == target { return }
        closeChildren(of: level)
        guard let target, child < PanelController.levels else { return }
        highlighted[level] = rowID
        show(target, at: level + 1)
        place(level: level + 1, rowTop: screenTop(level: level, rowFrame: rowFrame))
    }

    /// Clicking an open overview card again closes its side menu.
    func toggleSelect(level: Int, rowID: String, target: PanelContent, rowFrame: CGRect) {
        if highlighted[level] == rowID { closeChildren(of: level) } else { select(level: level, rowID: rowID, target: target, rowFrame: rowFrame) }
    }

    /// The pointer entered a panel: cancel pending switches in its parents.
    func pointerEntered(level: Int) {
        cancelPending(through: level - 1)
    }

    private func cancelPending(through level: Int) {
        guard level >= 0 else { return }
        for i in 0...level {
            timers[i]?.invalidate()
            timers[i] = nil
            pendingRow[i] = nil
        }
    }

    // MARK: Monitors (outside click, Esc, ⌘,, ⌥)

    private func installMonitors() {
        guard monitors.isEmpty else { return }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            let window = event.window
            MainActor.assumeIsolated { self?.handleLocalClick(in: window) }
            return event
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged], handler: { [weak self] event in
            let isFlags = event.type == .flagsChanged
            let option = event.modifierFlags.contains(.option)
            let command = event.modifierFlags.contains(.command)
            let keyCode = event.keyCode
            let chars = isFlags ? nil : event.charactersIgnoringModifiers
            let consumed = MainActor.assumeIsolated {
                self?.handleKey(isFlags: isFlags, option: option, command: command, keyCode: keyCode, chars: chars) ?? false
            }
            return consumed ? nil : event
        }) { monitors.append(m) }
    }

    private func handleLocalClick(in window: NSWindow?) {
        let inPanel = panels.contains { $0 === window }
        let inStatus = statusBar?.isStatusButtonWindow(window) ?? false
        if !inPanel && !inStatus { close() }
    }

    /// Returns true when the key event was handled (Esc closes, ⌘, opens settings).
    private func handleKey(isFlags: Bool, option: Bool, command: Bool, keyCode: UInt16, chars: String?) -> Bool {
        if isFlags {
            model.optionKeyDown = option
            return false
        }
        if keyCode == 53 { close(); return true }  // Esc
        if command && chars == "," {
            var id: String?
            if case .itemMenu(let itemID, _, _)? = contents[0] { id = itemID }
            close()
            openSettings?(id)
            return true
        }
        return false
    }

    private func removeMonitors() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()
        model.optionKeyDown = false
    }
}

/// Reports a panel's content size so the controller can resize the window.
private struct PanelSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

/// UI layer: the SwiftUI root of one panel level.
struct PanelRoot: View {
    let level: Int
    let content: PanelContent
    @Environment(PanelController.self) private var panels

    var body: some View {
        Group {
            switch content {
            case .itemMenu(let id, let withOthers, let back):
                MetricMenuView(level: level, itemID: id, withOthers: withOthers, showBack: back)
            case .allMetrics:
                AllMetricsView(level: level)
            case .overview:
                OverviewView(level: level)
            case .breakdown(let id, let kind):
                BreakdownView(level: level, itemID: id, kind: kind)
            }
        }
        .fixedSize()
        .background(GeometryReader { g in Color.clear.preference(key: PanelSizeKey.self, value: g.size) })
        .onPreferenceChange(PanelSizeKey.self) { size in
            MainActor.assumeIsolated { panels.contentSizeChanged(level: level, size: size) }
        }
        .onHover { inside in if inside { panels.pointerEntered(level: level) } }
    }
}
