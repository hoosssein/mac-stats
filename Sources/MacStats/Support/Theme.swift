import AppKit
import StatsCore
import SwiftUI

// UI layer: colors. Matches the wireframe: item color for the main series, orange and violet for others,
// green / yellow / red for states.

extension ItemColor {
    var nsColor: NSColor {
        switch self {
        case .blue: return .systemBlue
        case .orange: return .systemOrange
        case .violet: return .systemPurple
        case .green: return .systemGreen
        case .red: return .systemRed
        }
    }

    var color: Color { Color(nsColor: nsColor) }
}

enum Theme {
    static func nsColor(_ tint: SeriesTint, item: ItemConfig) -> NSColor {
        switch tint {
        case .item: return item.color.nsColor
        case .orange: return item.color == .orange ? .systemYellow : .systemOrange
        case .violet: return item.color == .violet ? .systemTeal : .systemPurple
        }
    }

    static func color(_ tint: SeriesTint, item: ItemConfig) -> Color { Color(nsColor: nsColor(tint, item: item)) }

    static func pill(_ level: PillLevel) -> Color {
        switch level {
        case .ok: return .green
        case .warning: return .yellow
        case .critical: return .red
        }
    }

    /// Bar color by fill level: normal, warning over 65%, critical over 85%.
    static func barColor(_ fraction: Double, base: Color) -> Color {
        fraction > 0.85 ? .red : fraction > 0.65 ? .yellow : base
    }

    static let menuWidth: CGFloat = 322
    static let breakdownWidth: CGFloat = 300
    static let rowHeight: CGFloat = 23
    static let mono = Font.system(size: 11.5, design: .monospaced)
    static let monoSmall = Font.system(size: 10.5, design: .monospaced)
    static let scaleFont = Font.system(size: 8.5, design: .monospaced)
}
