import AppKit
import StatsCore
import SwiftUI

// UI layer: small building blocks shared by menus, the overview and breakdown panels.

/// Captures a view's frame in the window's SwiftUI global space.
private struct FrameReader: ViewModifier {
    @Binding var frame: CGRect

    func body(content: Content) -> some View {
        content.background(GeometryReader { g in
            Color.clear
                .onAppear { frame = g.frame(in: .global) }
                .onChange(of: g.frame(in: .global)) { _, f in frame = f }
        })
    }
}

extension View {
    func readFrame(_ frame: Binding<CGRect>) -> some View { modifier(FrameReader(frame: frame)) }
}

/// A menu row. Hover opens `target` after the hover-intent delay (or only on click when `hoverOpens` is false).
/// Rows without a target run `action` on click.
struct MenuRow<Trailing: View>: View {
    let level: Int
    let id: String
    let label: String
    let target: PanelContent?
    let hoverOpens: Bool
    let height: CGFloat
    let action: (() -> Void)?
    let trailing: (Bool) -> Trailing

    @Environment(PanelController.self) private var panels
    @State private var hovered = false
    @State private var frame: CGRect = .zero

    init(level: Int, id: String, label: String, target: PanelContent? = nil, hoverOpens: Bool = true,
         height: CGFloat = Theme.rowHeight, action: (() -> Void)? = nil,
         @ViewBuilder trailing: @escaping (Bool) -> Trailing) {
        self.level = level; self.id = id; self.label = label; self.target = target
        self.hoverOpens = hoverOpens; self.height = height; self.action = action; self.trailing = trailing
    }

    var body: some View {
        let lit = panels.highlighted[level] == id || hovered
        HStack(spacing: 8) {
            Text(label)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            trailing(lit)
            if target != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(lit ? Color.white : Color.secondary)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(lit ? Color.white : Color.primary)
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .frame(height: height)
        .background(RoundedRectangle(cornerRadius: 5).fill(lit ? Color.accentColor : Color.clear))
        .contentShape(Rectangle())
        .readFrame($frame)
        .onHover { inside in
            hovered = inside
            if inside { panels.hover(level: level, rowID: id, target: hoverOpens ? target : nil, rowFrame: frame) }
        }
        .onTapGesture {
            if let target {
                panels.select(level: level, rowID: id, target: target, rowFrame: frame)
            } else {
                action?()
            }
        }
    }
}

extension MenuRow where Trailing == EmptyView {
    init(level: Int, id: String, label: String, target: PanelContent? = nil, action: (() -> Void)? = nil) {
        self.init(level: level, id: id, label: label, target: target, action: action) { _ in EmptyView() }
    }
}

/// The value text on the right of a row.
struct RowValue: View {
    let text: String?
    let lit: Bool

    var body: some View {
        if let text {
            Text(text)
                .font(Theme.mono)
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(lit ? Color.white.opacity(0.9) : Color.secondary)
        }
    }
}

struct Pill: View {
    let level: PillLevel
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Theme.pill(level)))
    }
}

struct MenuDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.2))
            .frame(height: 1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.7)
            Spacer()
            if let trailing { Text(trailing).font(.system(size: 10)) }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }
}

/// The period chips: 1m 5m 15m 1h 6h 24h 7d 30d.
struct RangeChips: View {
    @Binding var selection: ChartRange

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ChartRange.allCases, id: \.self) { r in
                Text(r.chip)
                    .font(Theme.monoSmall)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .foregroundStyle(selection == r ? Color.accentColor : Color.secondary)
                    .background(RoundedRectangle(cornerRadius: 4).fill(selection == r ? Color.accentColor.opacity(0.15) : Color.clear))
                    .contentShape(Rectangle())
                    .onTapGesture { selection = r }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Chart period \(r.label)")
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 7)
        .padding(.bottom, 3)
    }
}

/// A small line (or bar) chart without axes. Optional scale numbers sit inside the plot.
struct Sparkline: View {
    let values: [Double]
    let color: Color
    var maxValue: Double? = nil
    var bars = false
    var scale: (top: String, bottom: String)? = nil

    var body: some View {
        Canvas { ctx, size in
            guard values.count >= 2 else {
                var p = Path()
                p.move(to: CGPoint(x: 0, y: size.height - 0.5))
                p.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
                ctx.stroke(p, with: .color(color.opacity(0.35)), lineWidth: 1)
                return
            }
            let mx = maxValue ?? max((values.max() ?? 1) * 1.15, 1e-9)
            if bars {
                let n = min(values.count, Int(size.width / 3))
                for (i, v) in values.suffix(n).enumerated() {
                    let h = max(1, CGFloat(min(1, v / mx)) * size.height)
                    ctx.fill(Path(CGRect(x: CGFloat(i) * 3, y: size.height - h, width: 2, height: h)), with: .color(color))
                }
                return
            }
            let n = values.count
            func pt(_ i: Int) -> CGPoint {
                CGPoint(x: CGFloat(i) * size.width / CGFloat(n - 1),
                        y: size.height - 0.5 - CGFloat(min(1, max(0, values[i] / mx))) * (size.height - 1))
            }
            var line = Path()
            line.move(to: pt(0))
            for i in 1..<n { line.addLine(to: pt(i)) }
            var fill = line
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()
            ctx.fill(fill, with: .color(color.opacity(0.25)))
            ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
        }
        .overlay(alignment: .topLeading) {
            if let scale {
                VStack(alignment: .leading) {
                    ScaleLabel(text: scale.top)
                    Spacer(minLength: 0)
                    ScaleLabel(text: scale.bottom)
                }
                .padding(2)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A scale number drawn inside a chart, with a light outline for contrast.
struct ScaleLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.scaleFont)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 2)
            .background(RoundedRectangle(cornerRadius: 2).fill(Color(nsColor: .windowBackgroundColor).opacity(0.7)))
    }
}

/// The small first-letter icon used in lists.
struct InitialIcon: View {
    let name: String

    var body: some View {
        let letter = name.drop { "~/.".contains($0) }.first.map { String($0).uppercased() } ?? "?"
        Text(letter)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 17, height: 17)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
    }
}
