import AppKit
import Charts
import StatsCore
import SwiftUI

/// One drawable layer of a chart: a series with lower and upper edges per point.
private struct ChartLayer: Identifiable {
    struct Point { let date: Date; let lo: Double; let hi: Double; let edge: Double; let value: Double }
    let id: String
    let name: String
    let color: Color
    let points: [Point]
}

/// UI layer: an item's history chart (docs/kb/product-spec.md section 7).
/// Scale numbers sit inside the plot. Optional hover values show a crosshair and a tooltip,
/// and the chart holds still while they show.
struct MetricChart: View {
    let item: ItemConfig
    let range: ChartRange
    var height: CGFloat = 92
    var compact = false

    @Environment(AppModel.self) var model
    @State var frozen: [ChartSeries]? = nil
    @State var frozenEnd: Double = 0
    @State var hoverIndex: Int? = nil
    @State var hoverLocation: CGPoint = .zero

    private var valuesEnabled: Bool {
        switch model.config.general.chartValues {
        case .off: return false
        case .always: return true
        case .holdOption: return model.optionKeyDown || NSEvent.modifierFlags.contains(.option)
        }
    }

    var body: some View {
        let live = model.chartSeries(item, range: range)
        let series = frozen ?? live
        let end = frozen != nil ? frozenEnd : model.now
        let style = item.descriptor.chartStyle
        let layers = Self.layers(series, item: item, style: style)
        let peak = layers.flatMap { $0.points.map { max(abs($0.hi), abs($0.lo)) } }.max() ?? 0
        let presenter = model.presenter(item)
        let maxV = max(presenter.chartMax ?? Scale.niceMax(peak * 1.05), 1e-9)
        let domainY: ClosedRange<Double> = style == .mirror ? -maxV...maxV : 0...maxV
        let grid: [Double] = style == .mirror ? [-maxV, 0, maxV] : [0, maxV / 2, maxV]

        VStack(alignment: .leading, spacing: 2) {
            Chart {
                ForEach(layers) { layer in
                    ForEach(Array(layer.points.enumerated()), id: \.offset) { _, p in
                        AreaMark(x: .value("Time", p.date), yStart: .value("Low", p.lo), yEnd: .value("High", p.hi),
                                 series: .value("Series", layer.name))
                            .foregroundStyle(layer.color.opacity(0.25))
                            .interpolationMethod(.linear)
                        LineMark(x: .value("Time", p.date), y: .value("Edge", p.edge), series: .value("Series", layer.name))
                            .foregroundStyle(layer.color)
                            .lineStyle(StrokeStyle(lineWidth: 1.2, lineJoin: .round))
                            .interpolationMethod(.linear)
                    }
                }
                if let i = hoverIndex, let first = layers.first, first.points.indices.contains(i) {
                    RuleMark(x: .value("Time", first.points[i].date))
                        .foregroundStyle(Color.primary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    ForEach(layers) { layer in
                        if layer.points.indices.contains(i) {
                            PointMark(x: .value("Time", layer.points[i].date), y: .value("Edge", layer.points[i].edge))
                                .foregroundStyle(layer.color)
                                .symbolSize(24)
                        }
                    }
                }
            }
            .chartXScale(domain: Date(timeIntervalSince1970: end - range.seconds)...Date(timeIntervalSince1970: end))
            .chartYScale(domain: domainY)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(values: grid) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.secondary.opacity(0.3))
                }
            }
            .chartLegend(.hidden)
            .frame(height: height)
            .overlay(alignment: .topLeading) { scaleOverlay(presenter: presenter, maxV: maxV, style: style) }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(Color.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in hover(phase, proxy: proxy, geo: geo, live: live, layers: layers) }
                }
            }
            .overlay(alignment: .topLeading) { tooltip(layers: layers, presenter: presenter, style: style, end: end) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(item.name) chart, last \(range.label)")

            if !compact {
                HStack {
                    Text("−" + range.label)
                    Spacer()
                    Text("now")
                }
                .font(Theme.scaleFont)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Layers

    private static func layers(_ series: [ChartSeries], item: ItemConfig, style: ChartStyle) -> [ChartLayer] {
        // Align series from the newest point back, in case one series is shorter.
        let n = series.map(\.points.count).min() ?? 0
        guard n > 0 else { return [] }
        let aligned = series.map { Array($0.points.suffix(n)) }
        var lower = [Double](repeating: 0, count: n)
        var result: [ChartLayer] = []
        for (k, s) in series.enumerated() {
            var pts: [ChartLayer.Point] = []
            pts.reserveCapacity(n)
            for i in 0..<n {
                let p = aligned[k][i]
                let date = Date(timeIntervalSince1970: p.t)
                switch style {
                case .stacked:
                    let lo = lower[i], hi = lo + p.avg
                    pts.append(.init(date: date, lo: lo, hi: hi, edge: hi, value: p.avg))
                    lower[i] = hi
                case .mirror:
                    if k == 0 {
                        pts.append(.init(date: date, lo: 0, hi: p.avg, edge: p.avg, value: p.avg))
                    } else {
                        pts.append(.init(date: date, lo: -p.avg, hi: 0, edge: -p.avg, value: p.avg))
                    }
                case .area:
                    pts.append(.init(date: date, lo: 0, hi: p.avg, edge: p.avg, value: p.avg))
                }
            }
            result.append(ChartLayer(id: s.spec.key, name: s.spec.name, color: Theme.color(s.spec.tint, item: item), points: pts))
        }
        return result
    }

    // MARK: Scale numbers (inside the plot)

    @ViewBuilder
    private func scaleOverlay(presenter: ItemPresenter, maxV: Double, style: ChartStyle) -> some View {
        let top = presenter.axisLabel(maxV)
        let bottom = style == .mirror ? top : presenter.axisLabel(0)
        let middle = style == .mirror ? "0" : presenter.axisLabel(maxV / 2)
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                ScaleLabel(text: top)
                Spacer(minLength: 0)
                if !compact { ScaleLabel(text: middle) }
                Spacer(minLength: 0)
                ScaleLabel(text: bottom)
            }
            if style == .mirror && !compact {
                VStack(alignment: .trailing, spacing: 0) {
                    ScaleLabel(text: "▲ " + item.descriptor.series[0].name.lowercased())
                    Spacer(minLength: 0)
                    ScaleLabel(text: "▼ " + item.descriptor.series[1].name.lowercased())
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(2)
        .frame(height: height)
        .allowsHitTesting(false)
    }

    // MARK: Hover values

    private func hover(_ phase: HoverPhase, proxy: ChartProxy, geo: GeometryProxy, live: [ChartSeries], layers: [ChartLayer]) {
        switch phase {
        case .active(let location):
            guard valuesEnabled else { endHover(); return }
            if frozen == nil { frozen = live; frozenEnd = model.now }
            let plot = proxy.plotFrame.map { geo[$0] } ?? CGRect(origin: .zero, size: geo.size)
            guard let date: Date = proxy.value(atX: location.x - plot.minX) else { return }
            let frozenLayers = Self.layers(frozen ?? live, item: item, style: item.descriptor.chartStyle)
            guard let pts = frozenLayers.first?.points, !pts.isEmpty else { return }
            let t = date.timeIntervalSince1970
            var best = 0
            var bestDistance = Double.infinity
            for (i, p) in pts.enumerated() {
                let d = abs(p.date.timeIntervalSince1970 - t)
                if d < bestDistance { bestDistance = d; best = i }
            }
            hoverIndex = best
            hoverLocation = location
        case .ended:
            endHover()
        }
    }

    private func endHover() {
        frozen = nil
        hoverIndex = nil
    }

    @ViewBuilder
    private func tooltip(layers: [ChartLayer], presenter: ItemPresenter, style: ChartStyle, end: Double) -> some View {
        if let i = hoverIndex, let first = layers.first, first.points.indices.contains(i) {
            let date = first.points[i].date
            let ago = max(0, end - date.timeIntervalSince1970)
            let ordered = style == .stacked ? Array(layers.reversed()) : layers
            GeometryReader { geo in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(item.name) · \(TimeLabels.when(date, range: range, now: Date(timeIntervalSince1970: end)))")
                        .fontWeight(.semibold)
                    Text(TimeLabels.ago(ago)).foregroundStyle(.secondary).font(.system(size: 10, design: .monospaced))
                    ForEach(ordered) { layer in
                        if layer.points.indices.contains(i) {
                            HStack(spacing: 12) {
                                HStack(spacing: 5) {
                                    RoundedRectangle(cornerRadius: 2).fill(layer.color).frame(width: 8, height: 8)
                                    Text(layer.name)
                                }
                                Spacer(minLength: 0)
                                Text(presenter.valueText(layer.points[i].value)).fontWeight(.semibold)
                            }
                        }
                    }
                    if style == .stacked && layers.count > 1 {
                        Divider()
                        HStack {
                            Text("Total")
                            Spacer()
                            Text(presenter.valueText(layers.reduce(0) { $0 + ($1.points.indices.contains(i) ? $1.points[i].value : 0) }))
                                .fontWeight(.semibold)
                        }
                    }
                }
                .font(.system(size: 11, design: .monospaced))
                .monospacedDigit()
                .padding(8)
                .frame(width: 180, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 7).fill(.regularMaterial))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
                .offset(x: hoverLocation.x + 194 > geo.size.width ? max(0, hoverLocation.x - 194) : hoverLocation.x + 14,
                        y: 4)
            }
            .allowsHitTesting(false)
        }
    }
}
