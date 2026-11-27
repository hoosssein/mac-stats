import AppKit
import StatsCore

/// UI layer: draws one menu bar item into an image with Core Graphics (docs/kb/product-spec.md section 2.1).
/// Colors are resolved when the image is drawn, so text follows the menu bar's light or dark appearance.
@MainActor
enum MenuBarRenderer {
    static let height: CGFloat = 22
    private static let labelFont = NSFont.systemFont(ofSize: 8.5, weight: .semibold)
    private static let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    private static let twoFont = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .medium)

    /// Remembers the widest text seen per item and mode, so the item does not jitter as numbers change.
    private static var minWidths: [String: CGFloat] = [:]

    static func image(item: ItemConfig, presenter: ItemPresenter, spark: [Double], monochrome: Bool) -> NSImage {
        let label = item.showLabel ? item.label.uppercased() : nil
        let chartColor = monochrome ? NSColor.labelColor : item.color.nsColor
        // Keep items as narrow as possible: 2 pt after the label, 3 pt between other parts.
        let gap: CGFloat = 3
        let labelGap: CGFloat = 2

        var parts: [(width: CGFloat, draw: (CGFloat) -> Void)] = []

        if let label {
            let a = NSAttributedString(string: label, attributes: [.font: labelFont, .foregroundColor: NSColor.secondaryLabelColor])
            let w = ceil(a.size().width)
            parts.append((w, { x in a.draw(at: NSPoint(x: x, y: (height - a.size().height) / 2)) }))
        }

        func addNumber(_ text: String) {
            let a = NSAttributedString(string: text, attributes: [.font: numberFont, .foregroundColor: NSColor.labelColor])
            let key = "\(item.id).\(item.displayMode.rawValue).num"
            let w = stableWidth(key, ceil(a.size().width))
            parts.append((w, { x in a.draw(at: NSPoint(x: x + w - a.size().width, y: (height - a.size().height) / 2)) }))
        }

        func addSpark() {
            let w: CGFloat = 34, h: CGFloat = 15
            let values = spark
            let isBars = item.kind == .gpu
            let maxV = presenter.sparkMax ?? max(values.max() ?? 1, 1e-9) * 1.15
            parts.append((w, { x in
                let rect = NSRect(x: x, y: (height - h) / 2, width: w, height: h)
                drawSpark(values: values, in: rect, max: maxV, color: chartColor, bars: isBars)
            }))
        }

        switch item.displayMode {
        case .number:
            addNumber(presenter.menuBarText)
        case .chart:
            addSpark()
        case .chartAndNumber:
            addSpark()
            addNumber(presenter.menuBarText)
        case .gauge:
            let fill = presenter.gauge
            parts.append((5, { x in
                let r = NSRect(x: x, y: (height - 15) / 2, width: 5, height: 15)
                NSColor.tertiaryLabelColor.setFill()
                NSBezierPath(roundedRect: r, xRadius: 1.5, yRadius: 1.5).fill()
                chartColor.setFill()
                NSBezierPath(roundedRect: NSRect(x: r.minX, y: r.minY, width: 5, height: 15 * fill), xRadius: 1.5, yRadius: 1.5).fill()
            }))
            addNumber(presenter.menuBarText)
        case .twoValues:
            let lines = presenter.menuBarTwo
            let attrs: [NSAttributedString.Key: Any] = [.font: twoFont, .foregroundColor: NSColor.labelColor]
            let a = NSAttributedString(string: lines.0, attributes: attrs)
            let b = NSAttributedString(string: lines.1, attributes: attrs)
            let key = "\(item.id).two"
            let w = stableWidth(key, ceil(max(a.size().width, b.size().width)))
            parts.append((w, { x in
                b.draw(at: NSPoint(x: x, y: 1.5))
                a.draw(at: NSPoint(x: x, y: height / 2 - 0.5))
            }))
        }

        let hasLabel = label != nil
        let gaps: [CGFloat] = parts.indices.map { i in i == 0 ? 0 : (i == 1 && hasLabel ? labelGap : gap) }
        let total = ceil(parts.indices.reduce(0) { $0 + parts[$1].width + gaps[$1] })
        let image = NSImage(size: NSSize(width: max(total, 8), height: height), flipped: false) { _ in
            var x: CGFloat = 0
            for (i, p) in parts.enumerated() {
                x += gaps[i]
                p.draw(x)
                x += p.width
            }
            return true
        }
        image.isTemplate = monochrome
        return image
    }

    /// The generic Mac Stats icon (three bars).
    static func statsIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: height), flipped: false) { _ in
            NSColor.black.setFill()
            let y = (height - 13) / 2
            for (x, h) in [(0.0, 7.0), (6.0, 12.0), (12.0, 9.0)] as [(CGFloat, CGFloat)] {
                NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 3.5, height: h), xRadius: 1, yRadius: 1).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    static func resetWidths(for itemID: String) {
        minWidths = minWidths.filter { !$0.key.hasPrefix(itemID + ".") }
    }

    private static func stableWidth(_ key: String, _ w: CGFloat) -> CGFloat {
        let v = max(minWidths[key] ?? 0, w)
        minWidths[key] = v
        return v
    }

    private static func drawSpark(values: [Double], in rect: NSRect, max maxV: Double, color: NSColor, bars: Bool) {
        guard values.count >= 2, maxV > 0 else {
            NSColor.tertiaryLabelColor.setStroke()
            let p = NSBezierPath()
            p.move(to: NSPoint(x: rect.minX, y: rect.minY + 0.5))
            p.line(to: NSPoint(x: rect.maxX, y: rect.minY + 0.5))
            p.stroke()
            return
        }
        if bars {
            let vals = resampleMax(values, to: Int(rect.width / 3))
            color.setFill()
            for (i, v) in vals.enumerated() {
                let h = Swift.max(1, CGFloat(Swift.min(1, v / maxV)) * rect.height)
                NSRect(x: rect.minX + CGFloat(i) * 3, y: rect.minY, width: 2, height: h).fill()
            }
            return
        }
        let n = values.count
        func pt(_ i: Int) -> NSPoint {
            NSPoint(x: rect.minX + CGFloat(i) * rect.width / CGFloat(n - 1),
                    y: rect.minY + CGFloat(Swift.min(1, Swift.max(0, values[i] / maxV))) * (rect.height - 1) + 0.5)
        }
        let line = NSBezierPath()
        line.move(to: pt(0))
        for i in 1..<n { line.line(to: pt(i)) }
        let fill = line.copy() as! NSBezierPath
        fill.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        fill.line(to: NSPoint(x: rect.minX, y: rect.minY))
        fill.close()
        color.withAlphaComponent(0.25).setFill()
        fill.fill()
        color.setStroke()
        line.lineWidth = 1.2
        line.lineJoinStyle = .round
        line.stroke()
    }
}
