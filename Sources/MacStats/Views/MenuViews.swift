import AppKit
import StatsCore
import SwiftUI

// UI layer: the item menu, the All metrics list and the overview (docs/kb/product-spec.md sections 3–4).

/// An item's menu: header, period chips, chart, legend, detail rows, Other metrics, footer.
struct MetricMenuView: View {
    let level: Int
    let itemID: String
    let withOthers: Bool
    let showBack: Bool

    @Environment(AppModel.self) var model
    @Environment(PanelController.self) var panels

    var body: some View {
        Group {
            if let item = model.config.item(id: itemID) {
                content(item)
            } else {
                Text("This item was removed.")
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
        }
        .padding(6)
        .frame(width: Theme.menuWidth)
    }

    @ViewBuilder
    private func content(_ item: ItemConfig) -> some View {
        let p = model.presenter(item)
        VStack(alignment: .leading, spacing: 0) {
            if showBack {
                MenuRow(level: level, id: "back", label: "‹ All items", action: { panels.replaceRoot(.overview) })
                MenuDivider()
            }
            HStack(alignment: .firstTextBaseline) {
                Text(item.name).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(p.bigValue).font(.system(size: 19, weight: .semibold, design: .monospaced)).monospacedDigit()
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            Text(p.subLine)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.top, 3)
            RangeChips(selection: model.itemBinding(item.id, \.menuRange, fallback: item.menuRange))
            MetricChart(item: item, range: item.menuRange)
                .padding(.horizontal, 4)
            Legend(item: item)
            ForEach(p.rows) { row in
                if row.separatorBefore { MenuDivider() }
                MenuRow(level: level, id: "row:" + row.id, label: row.label,
                        target: row.breakdown.map { .breakdown(itemID: item.id, kind: $0) }) { lit in
                    if let pill = row.pillLevel, let text = row.value {
                        Pill(level: pill, text: text)
                    } else {
                        RowValue(text: row.value, lit: lit)
                    }
                }
            }
            if withOthers && model.config.menu.showOtherMetrics {
                OtherMetricsList(level: level, excluding: item.id, title: "Other metrics")
            }
            MenuDivider()
            ItemFooter(level: level, item: item)
        }
    }
}

struct Legend: View {
    let item: ItemConfig

    var body: some View {
        HStack(spacing: 12) {
            ForEach(item.descriptor.series, id: \.key) { s in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(Theme.color(s.tint, item: item)).frame(width: 8, height: 8)
                    Text(s.name)
                }
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.top, 3)
        .padding(.bottom, 4)
    }
}

/// One summary row per item with Menu on. Hover (or click) opens that item's full menu to the side.
struct OtherMetricsList: View {
    let level: Int
    let excluding: String?
    let title: String

    @Environment(AppModel.self) var model

    var body: some View {
        let items = model.config.menuItems.filter { $0.id != excluding }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                MenuDivider()
                SectionHeader(title: title, trailing: "\(items.count)")
                ForEach(items) { x in
                    let mini = model.config.menu.listStyle == .miniCharts
                    MenuRow(level: level, id: "sum:" + x.id, label: x.name,
                            target: .itemMenu(itemID: x.id, withOthers: false, back: false),
                            hoverOpens: model.config.menu.sideMenuOpens == .onHover,
                            height: mini ? 36 : 26) { lit in
                        SummaryValue(item: x, lit: lit, mini: mini)
                    }
                }
            }
        }
    }
}

struct SummaryValue: View {
    let item: ItemConfig
    let lit: Bool
    let mini: Bool

    @Environment(AppModel.self) var model

    var body: some View {
        let p = model.presenter(item)
        HStack(spacing: 8) {
            if item.summaryStyle == .valueAndChart || mini {
                Sparkline(values: Array(model.spark(item).suffix(60)), color: lit ? .white : item.color.color,
                          maxValue: p.sparkMax, bars: item.kind == .gpu)
                    .frame(width: mini ? 86 : 40, height: mini ? 24 : 13)
            }
            RowValue(text: p.summaryText, lit: lit)
        }
    }
}

struct ItemFooter: View {
    let level: Int
    let item: ItemConfig

    @Environment(AppModel.self) var model
    @Environment(PanelController.self) var panels

    var body: some View {
        VStack(spacing: 0) {
            MenuRow(level: level, id: "f:am", label: "Open Activity Monitor", action: {
                panels.close()
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
            })
            MenuRow(level: level, id: "f:settings", label: "Item settings…", action: {
                panels.close()
                panels.openSettings?(item.id)
            }) { lit in RowValue(text: "⌘,", lit: lit) }
            let inBar = model.config.item(id: item.id)?.showInMenuBar ?? false
            MenuRow(level: level, id: "f:bar", label: inBar ? "Hide from menu bar" : "Show in menu bar", action: {
                model.update { c in
                    if let i = c.index(of: item.id) { c.items[i].showInMenuBar.toggle() }
                }
            })
        }
    }
}

struct AppFooter: View {
    let level: Int

    @Environment(PanelController.self) var panels

    var body: some View {
        VStack(spacing: 0) {
            MenuRow(level: level, id: "f:settings", label: "Settings…", action: {
                panels.close()
                panels.openSettings?(nil)
            }) { lit in RowValue(text: "⌘,", lit: lit) }
            MenuRow(level: level, id: "f:quit", label: "Quit Mac Stats", action: { NSApp.terminate(nil) }) { lit in
                RowValue(text: "⌘Q", lit: lit)
            }
        }
    }
}

/// The Mac Stats icon's list in item-menu mode.
struct AllMetricsView: View {
    let level: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("All metrics").font(.system(size: 13, weight: .semibold)).padding(.horizontal, 8).padding(.top, 6)
            Text("Hover a metric to open its menu.")
                .font(.system(size: 11.5)).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.top, 3)
            OtherMetricsList(level: level, excluding: nil, title: "Metrics")
            MenuDivider()
            AppFooter(level: level)
        }
        .padding(6)
        .frame(width: Theme.menuWidth)
    }
}

/// The overview: one card per item with Menu on, in the shared order.
struct OverviewView: View {
    let level: Int

    @Environment(AppModel.self) var model

    var body: some View {
        let items = model.config.menuItems
        let cols = max(1, min(3, model.config.menu.overviewColumns))
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("All items").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(items.count) items · click one for its menu").font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            RangeChips(selection: model.binding(\.menu.overviewRange))
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(250), spacing: 6), count: cols), spacing: 6) {
                ForEach(items) { x in OverviewCardView(level: level, item: x) }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            MenuDivider()
            AppFooter(level: level)
        }
        .padding(6)
        .frame(width: CGFloat(cols) * 250 + CGFloat(cols - 1) * 6 + 24)
    }
}

struct OverviewCardView: View {
    let level: Int
    let item: ItemConfig

    @Environment(AppModel.self) var model
    @Environment(PanelController.self) var panels
    @State var frame: CGRect = .zero
    @State var hovered = false

    var body: some View {
        let p = model.presenter(item)
        let rowID = "card:" + item.id
        let open = panels.highlighted[level] == rowID
        let isAnchor = panels.anchorID == item.id
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.name).fontWeight(.semibold).lineLimit(1)
                Spacer(minLength: 4)
                Text(p.bigValue).font(.system(size: 14, weight: .semibold, design: .monospaced)).monospacedDigit().lineLimit(1)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }
            if model.config.menu.overviewCard != .valueOnly {
                MetricChart(item: item, range: model.config.menu.overviewRange, height: 58, compact: true)
            }
            if model.config.menu.overviewCard == .full {
                let details = p.cardDetails
                HStack {
                    Text(details.first ?? "")
                    Spacer(minLength: 6)
                    Text(details.count > 1 ? details[1] : "")
                }
                .font(Theme.monoSmall)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .font(.system(size: 12.5))
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 8).fill(open ? Color.accentColor.opacity(0.15) : hovered ? Color.secondary.opacity(0.08) : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(open || isAnchor ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: open || isAnchor ? 1 : 0.5))
        .contentShape(Rectangle())
        .readFrame($frame)
        .onHover { hovered = $0 }
        .onTapGesture {
            if model.config.menu.cardOpens == .beside {
                panels.toggleSelect(level: level, rowID: rowID, target: .itemMenu(itemID: item.id, withOthers: false, back: false), rowFrame: frame)
            } else {
                panels.replaceRoot(.itemMenu(itemID: item.id, withOthers: false, back: true))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(item.name), \(p.bigValue). Open its menu.")
    }
}
