import AppKit
import Observation
import StatsCore
import SwiftUI
import UniformTypeIdentifiers

// UI layer: the Settings window (docs/kb/product-spec.md section 9, docs/kb/configuration.md).

enum SettingsTab: Hashable { case items, menu, general, history }

@MainActor
@Observable
final class SettingsRouter {
    var tab: SettingsTab = .items
    var selection: String? = "cpu"
}

@MainActor
final class SettingsWindowController {
    private let model: AppModel
    private let router = SettingsRouter()
    private var window: NSWindow?

    init(model: AppModel) { self.model = model }

    func show(itemID: String?) {
        if let itemID {
            router.tab = .items
            router.selection = itemID
        }
        if window == nil {
            let host = NSHostingController(rootView: SettingsView().environment(model).environment(router))
            let w = NSWindow(contentViewController: host)
            w.title = "Mac Stats Settings"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @Environment(SettingsRouter.self) var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            ItemsSettings().tabItem { Text("Items") }.tag(SettingsTab.items)
            MenuSettings().tabItem { Text("Menu") }.tag(SettingsTab.menu)
            GeneralSettings().tabItem { Text("General") }.tag(SettingsTab.general)
            HistorySettings().tabItem { Text("History") }.tag(SettingsTab.history)
        }
        .padding(16)
        .frame(width: 800, height: 560)
    }
}

// MARK: Items

private struct AddOption: Identifiable {
    var id: String { title }
    let title: String
    let kind: MetricKind
    let target: String?
    let name: String?
    let label: String?
}

struct ItemsSettings: View {
    @Environment(AppModel.self) var model
    @Environment(SettingsRouter.self) var router

    var body: some View {
        @Bindable var router = router
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("ITEM")
                    Spacer()
                    Text("MENU BAR").frame(width: 64)
                    Text("MENU").frame(width: 44)
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                List(selection: $router.selection) {
                    StatsIconRow().tag("all")
                    ForEach(model.config.items) { item in
                        ItemListRow(item: item).tag(item.id)
                    }
                    .onMove { from, to in model.update { $0.items.move(fromOffsets: from, toOffset: to) } }
                }
                .listStyle(.bordered)
                .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                    guard press.modifiers.contains(.option), let id = router.selection, id != "all" else { return .ignored }
                    model.update { $0.move(id: id, by: press.key == .upArrow ? -1 : 1) }
                    return .handled
                }
                HStack {
                    Menu("+ Add item") {
                        let options = addOptions()
                        if options.isEmpty { Text("Every item is already in the list.") }
                        ForEach(options) { o in
                            Button(o.title) {
                                var added: ItemConfig?
                                model.update { added = $0.add(kind: o.kind, target: o.target, name: o.name, label: o.label) }
                                router.selection = added?.id
                            }
                        }
                    }
                    .fixedSize()
                    Button("− Remove") {
                        guard let id = router.selection, id != "all" else { return }
                        model.update { $0.remove(id: id) }
                        router.selection = model.config.items.first?.id ?? "all"
                    }
                    .disabled(router.selection == nil || router.selection == "all")
                }
                Text("Drag to reorder, or select and press ⌥↑ / ⌥↓. A new item starts in the menu only. Network and disk usage can be added more than once: one item per interface or volume.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 330)
            Divider().padding(.horizontal, 12)
            ScrollView {
                if router.selection == "all" {
                    StatsIconDetail()
                } else if let id = router.selection, model.config.item(id: id) != nil {
                    ItemDetail(itemID: id)
                } else {
                    Text("Pick an item on the left.").foregroundStyle(.secondary).padding(.top, 40)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func addOptions() -> [AddOption] {
        let items = model.config.items
        var options: [AddOption] = []
        for kind in [MetricKind.cpu, .memory, .gpu, .diskIO] where !items.contains(where: { $0.kind == kind }) {
            options.append(AddOption(title: MetricDescriptor.of(kind).name, kind: kind, target: nil, name: nil, label: nil))
        }
        if !items.contains(where: { $0.kind == .network && $0.target == nil }) {
            options.append(AddOption(title: "Network · all interfaces", kind: .network, target: nil, name: nil, label: nil))
        }
        for i in model.live.network?.interfaces ?? [] where !i.isTunnel || i.ipv4 != nil {
            guard !items.contains(where: { $0.kind == .network && $0.target == i.bsdName }) else { continue }
            options.append(AddOption(title: "Network · \(i.displayName) (\(i.bsdName))", kind: .network, target: i.bsdName,
                                     name: "Network · \(i.displayName)", label: "NET"))
        }
        for v in model.live.diskUsage?.volumes ?? [] {
            let target = v.isRoot ? "/" : v.path
            guard !items.contains(where: { $0.kind == .diskUsage && ($0.target ?? "/") == target }) else { continue }
            let label = String(v.name.split(separator: " ").first?.prefix(4) ?? "DISK").uppercased()
            options.append(AddOption(title: "Disk usage · \(v.name)", kind: .diskUsage, target: target,
                                     name: v.isRoot ? nil : "Disk usage · \(v.name)", label: v.isRoot ? nil : label))
        }
        return options
    }
}

private struct StatsIconRow: View {
    @Environment(AppModel.self) var model

    var body: some View {
        let auto = model.config.barItems.isEmpty
        HStack {
            Image(systemName: "chart.bar.fill").frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text("Mac Stats icon").fontWeight(.medium)
                Text(auto ? "shown automatically" : "opens all metrics").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { model.config.statsIconVisible }, set: { v in model.update { $0.showStatsIcon = v } }))
                .labelsHidden().toggleStyle(.switch).controlSize(.mini).frame(width: 64)
                .accessibilityLabel("Show the Mac Stats icon in the menu bar")
            Text("—").foregroundStyle(.secondary).frame(width: 44)
        }
        .padding(.vertical, 2)
    }
}

private struct ItemListRow: View {
    let item: ItemConfig
    @Environment(AppModel.self) var model

    var body: some View {
        let state: (String, Bool) = item.showInMenuBar ? (item.displayMode.title + (item.showInMenu ? "" : " · bar only"), false)
            : item.showInMenu ? ("menu only", true) : ("hidden", false)
        HStack {
            Image(systemName: "line.3.horizontal").foregroundStyle(.secondary).frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).fontWeight(.medium).lineLimit(1)
                Text(state.0).font(.system(size: 11, design: .monospaced)).foregroundStyle(state.1 ? Color.accentColor : Color.secondary)
            }
            .opacity(!item.showInMenuBar && !item.showInMenu ? 0.5 : 1)
            Spacer()
            Toggle("", isOn: model.itemBinding(item.id, \.showInMenuBar, fallback: false))
                .labelsHidden().toggleStyle(.switch).controlSize(.mini).frame(width: 64)
                .accessibilityLabel("Show \(item.name) in the menu bar")
            Toggle("", isOn: model.itemBinding(item.id, \.showInMenu, fallback: false))
                .labelsHidden().toggleStyle(.switch).controlSize(.mini).frame(width: 44)
                .accessibilityLabel("Show \(item.name) in the menu")
        }
        .padding(.vertical, 2)
    }
}

private struct StatsIconDetail: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Preview") { Image(systemName: "chart.bar.fill") }
                LabeledContent("Opens") {
                    Text("A menu with every metric whose Menu switch is on. Hover one to open its full menu to the side.")
                }
                LabeledContent("When it shows") {
                    Text("When its switch is on, and always when no other item is in the menu bar. So the app can never disappear.")
                }
            } header: {
                Text("Mac Stats icon").font(.headline)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ItemDetail: View {
    let itemID: String
    @Environment(AppModel.self) var model

    var body: some View {
        let item = model.config.item(id: itemID)!
        let p = model.presenter(item)
        Form {
            Section {
                LabeledContent("Preview") {
                    Image(nsImage: MenuBarRenderer.image(item: item, presenter: p, spark: model.spark(item),
                                                         monochrome: model.config.general.menuBarChartColor == .monochrome))
                        .padding(.horizontal, 6)
                        .frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
                }
                Picker("Show in menu bar as", selection: model.itemBinding(itemID, \.displayMode, fallback: item.displayMode)) {
                    ForEach(DisplayMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Row in Other metrics", selection: model.itemBinding(itemID, \.summaryStyle, fallback: item.summaryStyle)) {
                    ForEach(SummaryStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("Show “\(item.label)” before the value", isOn: model.itemBinding(itemID, \.showLabel, fallback: true))
                Picker("Value shown", selection: model.itemBinding(itemID, \.valueShown, fallback: 0)) {
                    ForEach(Array(item.descriptor.valueOptions.enumerated()), id: \.offset) { i, title in Text(title).tag(i) }
                }
                Picker("Menu bar chart covers", selection: model.itemBinding(itemID, \.menuBarChartSeconds, fallback: 60)) {
                    Text("Last 30 s").tag(30)
                    Text("Last 1 min").tag(60)
                    Text("Last 2 min").tag(120)
                }
                Picker("Menu chart opens at", selection: model.itemBinding(itemID, \.menuRange, fallback: item.menuRange)) {
                    ForEach(ChartRange.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker("Sample every", selection: model.itemBinding(itemID, \.sampleSeconds, fallback: 1)) {
                    Text("1 s").tag(1)
                    Text("2 s").tag(2)
                    Text("5 s").tag(5)
                }
                Picker("Rows in breakdown panels", selection: model.itemBinding(itemID, \.breakdownRows, fallback: 8)) {
                    Text("5 rows").tag(5)
                    Text("8 rows").tag(8)
                    Text("12 rows").tag(12)
                }
                LabeledContent("Color") {
                    HStack(spacing: 8) {
                        ForEach(ItemColor.allCases, id: \.self) { c in
                            Circle()
                                .fill(c.color)
                                .frame(width: 18, height: 18)
                                .overlay(Circle().stroke(Color.primary, lineWidth: item.color == c ? 2 : 0).padding(-3))
                                .onTapGesture { model.update { cfg in if let i = cfg.index(of: itemID) { cfg.items[i].color = c } } }
                                .accessibilityLabel(c.title)
                                .accessibilityAddTraits(item.color == c ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                }
            } header: {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.name).font(.headline)
                    Text(p.subLine).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Menu

struct MenuSettings: View {
    @Environment(AppModel.self) var model

    var body: some View {
        Form {
            Section {
                Picker("Clicking a menu bar item opens", selection: model.binding(\.menu.clickOpens)) {
                    ForEach(ClickOpens.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("⌥-click an item to open the other one.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Item menu") {
                Toggle("Under the details, show the other metrics", isOn: model.binding(\.menu.showOtherMetrics))
                Picker("List style", selection: model.binding(\.menu.listStyle)) {
                    ForEach(ListStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Open a metric's side menu", selection: model.binding(\.menu.sideMenuOpens)) {
                    ForEach(SideMenuOpens.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            Section("Overview") {
                Picker("Clicking a card or its chart", selection: model.binding(\.menu.cardOpens)) {
                    ForEach(CardOpens.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Columns", selection: model.binding(\.menu.overviewColumns)) {
                    Text("1").tag(1)
                    Text("2").tag(2)
                    Text("3").tag(3)
                }
                .pickerStyle(.segmented)
                Picker("Each card shows", selection: model.binding(\.menu.overviewCard)) {
                    ForEach(OverviewCard.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                LabeledContent("Chart period") {
                    Text("Pick it with the chips at the top of the overview. All cards share it.").foregroundStyle(.secondary)
                }
            }
            Section("Both") {
                LabeledContent("Which metrics, in which order") {
                    Text("Each item's Menu switch in the Items tab controls both the Other metrics list and the overview cards. Both follow the menu bar order.")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Default") {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("Click opens the item's own menu. CPU, Memory and Network in the menu bar. All six metrics in the menu and the overview. Compact rows. Two overview columns, and cards open their menu beside the overview.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                        Button("Reset to default") { model.update { $0.resetItemsAndMenu() } }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: General

struct GeneralSettings: View {
    @Environment(AppModel.self) var model

    var body: some View {
        Form {
            Picker("Appearance", selection: model.binding(\.general.appearance)) {
                ForEach(Appearance.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Chart values on hover", selection: model.binding(\.general.chartValues)) {
                ForEach(ChartValues.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Text("Shows the time and each line's value under the pointer. Off by default.").font(.caption).foregroundStyle(.secondary)
            Picker("Menu bar charts", selection: model.binding(\.general.menuBarChartColor)) {
                ForEach(MenuBarChartColor.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Toggle("Start Mac Stats when you log in", isOn: model.binding(\.general.openAtLogin))
            Picker("On battery", selection: model.binding(\.general.onBattery)) {
                ForEach(OnBattery.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("When the screen is locked", selection: model.binding(\.general.whenLocked)) {
                ForEach(WhenLocked.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Units", selection: model.binding(\.general.units)) {
                ForEach(Units.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            LabeledContent("Configuration") {
                HStack {
                    Button("Export…") { exportConfig() }
                    Button("Import…") { importConfig() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func exportConfig() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Mac Stats config.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url, let data = try? ConfigStore.encode(model.config) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url), let config = try? ConfigStore.decode(data) else { return }
        model.replaceConfig(config)
    }
}

// MARK: History

struct HistorySettings: View {
    @Environment(AppModel.self) var model
    @State var confirmDelete = false

    var body: some View {
        Form {
            Picker("Keep history for", selection: model.binding(\.history.keepDays)) {
                ForEach(HistoryConfig.keepDaysOptions, id: \.self) { Text("\($0) days").tag($0) }
            }
            Picker("Per-app history", selection: model.binding(\.history.perAppHistory)) {
                ForEach(PerAppHistory.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            LabeledContent("Stored on disk") {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(UnitFormatter(units: model.units).bytes(model.historyFileSize))
                        .font(.system(.body, design: .monospaced))
                    Text(model.database.url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.database.url]) }
                }
            }
            LabeledContent("Clear") {
                Button("Delete all history…") { confirmDelete = true }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Delete all history?", isPresented: $confirmDelete) {
            Button("Delete all history", role: .destructive) { model.deleteAllHistory() }
        } message: {
            Text("Charts start again from now. Settings are kept.")
        }
    }
}
