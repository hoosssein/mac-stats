import StatsCore
import SwiftUI

/// UI layer: a breakdown panel (list, bars or key-value lines). See docs/kb/product-spec.md section 5.
struct BreakdownView: View {
    let level: Int
    let itemID: String
    let kind: BreakdownKind

    @Environment(AppModel.self) var model

    var body: some View {
        Group {
            if let item = model.config.item(id: itemID) {
                content(item, model.breakdown(item, kind))
            } else {
                Text("This item was removed.").foregroundStyle(.secondary).padding(12)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .frame(width: Theme.breakdownWidth)
    }

    @ViewBuilder
    private func content(_ item: ItemConfig, _ m: BreakdownModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text(m.title).font(.system(size: 13, weight: .semibold))
                Text(m.subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
            Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 1).padding(.bottom, 4)

            if let key = m.chartKey {
                let pts = model.points(key, range: m.chartRange)
                let mx = m.chartMax ?? Scale.niceMax((pts.map(\.max).max() ?? 0) * 1.1)
                Sparkline(values: pts.map(\.avg), color: item.color.color, maxValue: mx,
                          scale: (scaleText(key, mx, item), scaleText(key, 0, item)))
                    .frame(height: 44)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }

            switch m.content {
            case .list(let rows):
                ForEach(rows) { row in
                    HStack(spacing: 8) {
                        InitialIcon(name: row.name)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(row.name).lineLimit(1).truncationMode(.middle)
                            if let sub = row.sub {
                                Text(sub).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 4)
                        if row.sparkKey != nil {
                            Sparkline(values: model.appSpark(row.sparkKey), color: item.color.color)
                                .frame(width: 40, height: 14)
                        }
                        Text(row.value).font(Theme.mono).monospacedDigit().lineLimit(1)
                    }
                    .font(.system(size: 12.5))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
            case .bars(let groups):
                ForEach(groups) { g in
                    Text(g.name.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.7)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                    ForEach(g.rows) { r in
                        HStack(spacing: 8) {
                            Text(r.label).font(Theme.mono).lineLimit(1).frame(width: m.wideLabels ? 92 : 30, alignment: .leading)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.15))
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Theme.barColor(r.fraction, base: item.color.color))
                                        .frame(width: geo.size.width * CGFloat(min(1, max(0, r.fraction))))
                                }
                            }
                            .frame(height: 7)
                            Text(r.text).font(Theme.mono).monospacedDigit().lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                    }
                }
            case .keyValue(let kv):
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                    ForEach(kv) { pair in
                        GridRow {
                            Text(pair.key).foregroundStyle(.secondary)
                            Text(pair.value).font(.system(size: 12, design: .monospaced)).monospacedDigit()
                                .gridColumnAlignment(.trailing)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                }
                .font(.system(size: 12.5))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }

            if m.moreCount > 0 {
                Text("+ \(m.moreCount) more · change in item settings")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.top, 4)
            }
            if let empty = m.emptyText, isEmpty(m.content) {
                Text(empty).font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 6)
            }
            if let action = m.action {
                Button(action == .scanFolders ? "Scan now" : "Cancel scan") {
                    if action == .scanFolders { model.startFolderScan() } else { model.cancelFolderScan() }
                }
                .controlSize(.small)
                .padding(.horizontal, 8)
                .padding(.top, 6)
            }
            if let note = m.note {
                Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 1).padding(.horizontal, 8).padding(.top, 8)
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .padding(.top, 6)
            }
        }
    }

    private func isEmpty(_ c: BreakdownModel.Content) -> Bool {
        switch c {
        case .list(let r): return r.isEmpty
        case .bars(let g): return g.allSatisfy { $0.rows.isEmpty }
        case .keyValue(let kv): return kv.isEmpty
        }
    }

    /// Scale text for the small charts in key-value panels.
    private func scaleText(_ key: String, _ v: Double, _ item: ItemConfig) -> String {
        let fmt = UnitFormatter(units: model.units)
        if key.hasSuffix(".load") { return String(format: v == v.rounded() ? "%.0f" : "%.1f", v) }
        if key.hasSuffix(".pressure") { return fmt.axisPercent(v) }
        return fmt.axisBytes(v)
    }
}
