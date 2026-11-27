import Foundation

// Model layer: the whole user configuration. Defaults must match docs/kb/configuration.md.
// Decoding is lenient: a missing key falls back to its default, so old files keep working.

public struct ItemConfig: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: MetricKind
    /// Network: interface BSD name (nil = all interfaces). Disk usage: volume path (nil = boot volume "/").
    public var target: String?
    /// Custom name for copies, for example "Disk usage · T7". Nil = the kind's name.
    public var customName: String?
    public var showInMenuBar: Bool
    public var showInMenu: Bool
    public var displayMode: DisplayMode
    public var summaryStyle: SummaryStyle
    public var showLabel: Bool
    public var valueShown: Int
    public var menuBarChartSeconds: Int
    public var menuRange: ChartRange
    public var sampleSeconds: Int
    public var breakdownRows: Int
    public var color: ItemColor
    /// Custom short label for copies, for example "T7". Nil = the kind's label.
    public var customLabel: String?

    public var descriptor: MetricDescriptor { .of(kind) }
    public var name: String { customName ?? descriptor.name }
    public var label: String { customLabel ?? descriptor.label }

    public static func make(kind: MetricKind, id: String, target: String? = nil,
                            showInMenuBar: Bool, showInMenu: Bool = true,
                            name: String? = nil, label: String? = nil) -> ItemConfig {
        let d = MetricDescriptor.of(kind)
        return ItemConfig(id: id, kind: kind, target: target, customName: name,
                          showInMenuBar: showInMenuBar, showInMenu: showInMenu,
                          displayMode: d.defaultMode, summaryStyle: d.defaultSummary,
                          showLabel: true, valueShown: 0, menuBarChartSeconds: 60,
                          menuRange: d.defaultRange, sampleSeconds: 1, breakdownRows: 8,
                          color: d.defaultColor, customLabel: label)
    }

    public init(id: String, kind: MetricKind, target: String?, customName: String?,
                showInMenuBar: Bool, showInMenu: Bool, displayMode: DisplayMode, summaryStyle: SummaryStyle,
                showLabel: Bool, valueShown: Int, menuBarChartSeconds: Int, menuRange: ChartRange,
                sampleSeconds: Int, breakdownRows: Int, color: ItemColor, customLabel: String?) {
        self.id = id; self.kind = kind; self.target = target; self.customName = customName
        self.showInMenuBar = showInMenuBar; self.showInMenu = showInMenu
        self.displayMode = displayMode; self.summaryStyle = summaryStyle; self.showLabel = showLabel
        self.valueShown = valueShown; self.menuBarChartSeconds = menuBarChartSeconds; self.menuRange = menuRange
        self.sampleSeconds = sampleSeconds; self.breakdownRows = breakdownRows; self.color = color
        self.customLabel = customLabel
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, target, customName, showInMenuBar, showInMenu, displayMode, summaryStyle, showLabel,
             valueShown, menuBarChartSeconds, menuRange, sampleSeconds, breakdownRows, color, customLabel
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(MetricKind.self, forKey: .kind)
        let id = try c.decode(String.self, forKey: .id)
        let base = ItemConfig.make(kind: kind, id: id, showInMenuBar: false)
        self.id = id
        self.kind = kind
        target = try c.decodeIfPresent(String.self, forKey: .target)
        customName = try c.decodeIfPresent(String.self, forKey: .customName)
        showInMenuBar = try c.decodeIfPresent(Bool.self, forKey: .showInMenuBar) ?? base.showInMenuBar
        showInMenu = try c.decodeIfPresent(Bool.self, forKey: .showInMenu) ?? base.showInMenu
        displayMode = (try? c.decodeIfPresent(DisplayMode.self, forKey: .displayMode)) ?? base.displayMode
        summaryStyle = (try? c.decodeIfPresent(SummaryStyle.self, forKey: .summaryStyle)) ?? base.summaryStyle
        showLabel = try c.decodeIfPresent(Bool.self, forKey: .showLabel) ?? base.showLabel
        valueShown = try c.decodeIfPresent(Int.self, forKey: .valueShown) ?? base.valueShown
        menuBarChartSeconds = ItemConfig.allowed((try? c.decodeIfPresent(Int.self, forKey: .menuBarChartSeconds)) ?? nil,
                                                 ItemConfig.menuBarChartSecondsOptions, base.menuBarChartSeconds)
        menuRange = (try? c.decodeIfPresent(ChartRange.self, forKey: .menuRange)) ?? base.menuRange
        sampleSeconds = ItemConfig.allowed((try? c.decodeIfPresent(Int.self, forKey: .sampleSeconds)) ?? nil,
                                           ItemConfig.sampleSecondsOptions, base.sampleSeconds)
        breakdownRows = ItemConfig.allowed((try? c.decodeIfPresent(Int.self, forKey: .breakdownRows)) ?? nil,
                                           ItemConfig.breakdownRowsOptions, base.breakdownRows)
        color = (try? c.decodeIfPresent(ItemColor.self, forKey: .color)) ?? base.color
        customLabel = try c.decodeIfPresent(String.self, forKey: .customLabel)
        if !base.descriptor.valueOptions.indices.contains(valueShown) { valueShown = 0 }
    }

    // Allowed values (docs/kb/configuration.md section 2). Anything else falls back to the default.
    public static let menuBarChartSecondsOptions = [30, 60, 120]
    public static let sampleSecondsOptions = [1, 2, 5]
    public static let breakdownRowsOptions = [5, 8, 12]

    static func allowed(_ value: Int?, _ options: [Int], _ fallback: Int) -> Int {
        guard let value, options.contains(value) else { return fallback }
        return value
    }
}

/// Decodes one array element and keeps nil instead of failing the whole array.
private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

public struct MenuConfig: Codable, Equatable, Sendable {
    public var clickOpens: ClickOpens = .itemMenu
    public var showOtherMetrics: Bool = true
    public var listStyle: ListStyle = .compactRows
    public var sideMenuOpens: SideMenuOpens = .onHover
    public var cardOpens: CardOpens = .beside
    public var overviewColumns: Int = 2
    public var overviewCard: OverviewCard = .full
    public var overviewRange: ChartRange = .m15

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MenuConfig()
        clickOpens = (try? c.decodeIfPresent(ClickOpens.self, forKey: .clickOpens)) ?? d.clickOpens
        showOtherMetrics = (try? c.decodeIfPresent(Bool.self, forKey: .showOtherMetrics)) ?? d.showOtherMetrics
        listStyle = (try? c.decodeIfPresent(ListStyle.self, forKey: .listStyle)) ?? d.listStyle
        sideMenuOpens = (try? c.decodeIfPresent(SideMenuOpens.self, forKey: .sideMenuOpens)) ?? d.sideMenuOpens
        cardOpens = (try? c.decodeIfPresent(CardOpens.self, forKey: .cardOpens)) ?? d.cardOpens
        overviewColumns = min(3, max(1, (try? c.decodeIfPresent(Int.self, forKey: .overviewColumns)) ?? d.overviewColumns))
        overviewCard = (try? c.decodeIfPresent(OverviewCard.self, forKey: .overviewCard)) ?? d.overviewCard
        overviewRange = (try? c.decodeIfPresent(ChartRange.self, forKey: .overviewRange)) ?? d.overviewRange
    }
}

public struct GeneralConfig: Codable, Equatable, Sendable {
    public var appearance: Appearance = .system
    public var chartValues: ChartValues = .off
    public var menuBarChartColor: MenuBarChartColor = .colored
    public var openAtLogin: Bool = true
    public var onBattery: OnBattery = .every2s
    public var whenLocked: WhenLocked = .pauseDrawing
    public var units: Units = .base1000

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GeneralConfig()
        appearance = (try? c.decodeIfPresent(Appearance.self, forKey: .appearance)) ?? d.appearance
        chartValues = (try? c.decodeIfPresent(ChartValues.self, forKey: .chartValues)) ?? d.chartValues
        menuBarChartColor = (try? c.decodeIfPresent(MenuBarChartColor.self, forKey: .menuBarChartColor)) ?? d.menuBarChartColor
        openAtLogin = (try? c.decodeIfPresent(Bool.self, forKey: .openAtLogin)) ?? d.openAtLogin
        onBattery = (try? c.decodeIfPresent(OnBattery.self, forKey: .onBattery)) ?? d.onBattery
        whenLocked = (try? c.decodeIfPresent(WhenLocked.self, forKey: .whenLocked)) ?? d.whenLocked
        units = (try? c.decodeIfPresent(Units.self, forKey: .units)) ?? d.units
    }
}

public struct HistoryConfig: Codable, Equatable, Sendable {
    public static let keepDaysOptions = [7, 30, 90]
    public var keepDays: Int = 30
    public var perAppHistory: PerAppHistory = .last15min

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = HistoryConfig()
        let days = (try? c.decodeIfPresent(Int.self, forKey: .keepDays)) ?? d.keepDays
        keepDays = HistoryConfig.keepDaysOptions.contains(days) ? days : d.keepDays
        perAppHistory = (try? c.decodeIfPresent(PerAppHistory.self, forKey: .perAppHistory)) ?? d.perAppHistory
    }
}

public struct AppConfig: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int = AppConfig.currentVersion
    /// The Mac Stats icon switch. The icon also shows when no item is in the menu bar.
    public var showStatsIcon: Bool = false
    public var items: [ItemConfig] = AppConfig.defaultItems
    public var menu = MenuConfig()
    public var general = GeneralConfig()
    public var history = HistoryConfig()

    public init() {}

    public static let `default` = AppConfig()

    /// Default items, in menu bar order. CPU, Memory and Network are in the menu bar; all six are in the menu.
    public static var defaultItems: [ItemConfig] {
        [
            .make(kind: .cpu, id: "cpu", showInMenuBar: true),
            .make(kind: .memory, id: "mem", showInMenuBar: true),
            .make(kind: .network, id: "net", showInMenuBar: true),
            .make(kind: .gpu, id: "gpu", showInMenuBar: false),
            .make(kind: .diskIO, id: "dio", showInMenuBar: false),
            .make(kind: .diskUsage, id: "du", target: "/", showInMenuBar: false),
        ]
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decodeIfPresent(Int.self, forKey: .version)) ?? AppConfig.currentVersion
        showStatsIcon = (try? c.decodeIfPresent(Bool.self, forKey: .showStatsIcon)) ?? false
        // One bad item is skipped; it does not throw away the whole list.
        if let list = try? c.decodeIfPresent([Lossy<ItemConfig>].self, forKey: .items) {
            items = list.compactMap(\.value)
        } else {
            items = AppConfig.defaultItems
        }
        menu = (try? c.decodeIfPresent(MenuConfig.self, forKey: .menu)) ?? MenuConfig()
        general = (try? c.decodeIfPresent(GeneralConfig.self, forKey: .general)) ?? GeneralConfig()
        history = (try? c.decodeIfPresent(HistoryConfig.self, forKey: .history)) ?? HistoryConfig()
        // Ids must be unique; drop later duplicates.
        var seen = Set<String>()
        items = items.filter { seen.insert($0.id).inserted }
    }

    // MARK: Queries

    /// Items with a menu bar slot, in order.
    public var barItems: [ItemConfig] { items.filter(\.showInMenuBar) }

    /// Items in the Other metrics list and the overview, in order.
    public var menuItems: [ItemConfig] { items.filter(\.showInMenu) }

    /// The Mac Stats icon shows when its switch is on, and always when no item is in the menu bar.
    public var statsIconVisible: Bool { showStatsIcon || barItems.isEmpty }

    public func item(id: String) -> ItemConfig? { items.first { $0.id == id } }

    public func index(of id: String) -> Int? { items.firstIndex { $0.id == id } }

    // MARK: Changes

    public mutating func update(_ item: ItemConfig) {
        if let i = index(of: item.id) { items[i] = item }
    }

    /// Moves an item one step up (-1) or down (+1).
    public mutating func move(id: String, by offset: Int) {
        guard let i = index(of: id) else { return }
        let j = i + offset
        guard items.indices.contains(j) else { return }
        items.swapAt(i, j)
    }

    /// Moves an item so it sits before the item `beforeID` (or at the end when nil).
    public mutating func move(id: String, before beforeID: String?) {
        guard id != beforeID, let i = index(of: id) else { return }
        let item = items.remove(at: i)
        if let beforeID, let j = index(of: beforeID) {
            items.insert(item, at: j)
        } else {
            items.append(item)
        }
    }

    public mutating func remove(id: String) {
        items.removeAll { $0.id == id }
    }

    /// Adds an item. A new item starts as menu only (docs/kb/product-spec.md section 1).
    @discardableResult
    public mutating func add(kind: MetricKind, target: String? = nil, name: String? = nil, label: String? = nil) -> ItemConfig {
        // Re-adding a default item (same kind and target) brings back its default id and settings.
        let base = AppConfig.defaultItems.first { $0.kind == kind && $0.target == target }
        let stem = AppConfig.makeID(kind: kind, target: target)
        var id = base?.id ?? stem
        var n = 2
        while index(of: id) != nil { id = "\(stem)-\(n)"; n += 1 }
        var item: ItemConfig
        if let base, base.id == id {
            item = base
        } else {
            item = ItemConfig.make(kind: kind, id: id, target: target, showInMenuBar: false, name: name, label: label)
        }
        item.showInMenuBar = false
        item.showInMenu = true
        items.append(item)
        return item
    }

    /// Restores the default item list, order, switches and menu settings. General and history are kept.
    public mutating func resetItemsAndMenu() {
        items = AppConfig.defaultItems
        showStatsIcon = false
        menu = MenuConfig()
    }

    static func makeID(kind: MetricKind, target: String?) -> String {
        guard let target, !target.isEmpty else { return kind.rawValue }
        let safe = target.map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
        return "\(kind.rawValue)-\(safe)"
    }
}
