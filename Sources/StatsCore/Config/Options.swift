import Foundation

// Model layer: every option the user can pick. Titles match docs/kb/configuration.md.

public enum MetricKind: String, Codable, CaseIterable, Sendable {
    case cpu, memory, network, gpu, diskIO, diskUsage
}

public enum DisplayMode: String, Codable, CaseIterable, Sendable {
    case number, chart, chartAndNumber, gauge, twoValues

    public var title: String {
        switch self {
        case .number: return "Number"
        case .chart: return "Chart"
        case .chartAndNumber: return "Chart + number"
        case .gauge: return "Gauge"
        case .twoValues: return "Two values"
        }
    }
}

public enum SummaryStyle: String, Codable, CaseIterable, Sendable {
    case valueAndChart, valueOnly, twoValues

    public var title: String {
        switch self {
        case .valueAndChart: return "Value + chart"
        case .valueOnly: return "Value only"
        case .twoValues: return "Two values"
        }
    }
}

public enum ChartRange: String, Codable, CaseIterable, Sendable {
    case m1 = "1m", m5 = "5m", m15 = "15m", h1 = "1h", h6 = "6h", h24 = "24h", d7 = "7d", d30 = "30d"

    public var seconds: Double {
        switch self {
        case .m1: return 60
        case .m5: return 300
        case .m15: return 900
        case .h1: return 3600
        case .h6: return 21_600
        case .h24: return 86_400
        case .d7: return 604_800
        case .d30: return 2_592_000
        }
    }

    /// Text used in "−5 min" under charts and in settings menus.
    public var label: String {
        switch self {
        case .m1: return "1 min"
        case .m5: return "5 min"
        case .m15: return "15 min"
        case .h1: return "1 h"
        case .h6: return "6 h"
        case .h24: return "24 h"
        case .d7: return "7 days"
        case .d30: return "30 days"
        }
    }

    /// The chip title, for example "5m".
    public var chip: String { rawValue }

    /// Which history tier serves this period (see docs/kb/architecture.md).
    public var tier: Int {
        switch self {
        case .m1, .m5, .m15, .h1: return 0
        case .h6, .h24: return 1
        case .d7: return 2
        case .d30: return 3
        }
    }
}

public enum ItemColor: String, Codable, CaseIterable, Sendable {
    case blue, orange, violet, green, red

    public var title: String { rawValue.capitalized }
}

public enum ClickOpens: String, Codable, CaseIterable, Sendable {
    case itemMenu, overview

    public var title: String { self == .itemMenu ? "The item's own menu" : "Overview of all items" }
}

public enum ListStyle: String, Codable, CaseIterable, Sendable {
    case compactRows, miniCharts

    public var title: String { self == .compactRows ? "Compact rows" : "Mini charts" }
}

public enum SideMenuOpens: String, Codable, CaseIterable, Sendable {
    case onHover, onClick

    public var title: String { self == .onHover ? "On hover" : "Only on click" }
}

public enum CardOpens: String, Codable, CaseIterable, Sendable {
    case beside, inPlace

    public var title: String { self == .beside ? "Opens its menu beside the overview" : "Opens its menu in place" }
}

public enum OverviewCard: String, Codable, CaseIterable, Sendable {
    case full, chart, valueOnly

    public var title: String {
        switch self {
        case .full: return "Value, chart and details"
        case .chart: return "Value and chart"
        case .valueOnly: return "Value only"
        }
    }
}

public enum Appearance: String, Codable, CaseIterable, Sendable {
    case system, light, dark

    public var title: String {
        switch self {
        case .system: return "Match system"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

public enum ChartValues: String, Codable, CaseIterable, Sendable {
    case off, holdOption, always

    public var title: String {
        switch self {
        case .off: return "Off"
        case .holdOption: return "Only while holding ⌥"
        case .always: return "Always"
        }
    }
}

public enum MenuBarChartColor: String, Codable, CaseIterable, Sendable {
    case colored, monochrome

    public var title: String { self == .colored ? "In color" : "One color, like the menu bar text" }
}

public enum OnBattery: String, Codable, CaseIterable, Sendable {
    case every2s, same, every5s

    public var title: String {
        switch self {
        case .every2s: return "Sample every 2 s"
        case .same: return "Same as on power"
        case .every5s: return "Sample every 5 s"
        }
    }

    /// The sampling interval to use on battery, given the interval on power.
    public func seconds(onPower: Int) -> Int {
        switch self {
        case .every2s: return max(onPower, 2)
        case .same: return onPower
        case .every5s: return max(onPower, 5)
        }
    }
}

public enum WhenLocked: String, Codable, CaseIterable, Sendable {
    case pauseDrawing, keepDrawing

    public var title: String { self == .pauseDrawing ? "Pause menu bar drawing" : "Keep drawing" }
}

public enum Units: String, Codable, CaseIterable, Sendable {
    case base1000, base1024, bitsForNetwork

    public var title: String {
        switch self {
        case .base1000: return "Bytes, base 1000 (like Finder)"
        case .base1024: return "Bytes, base 1024"
        case .bitsForNetwork: return "Bits for network"
        }
    }
}

public enum PerAppHistory: String, Codable, CaseIterable, Sendable {
    case last15min, off, last1h

    public var title: String {
        switch self {
        case .last15min: return "Last 15 min, top 20 apps"
        case .off: return "Off"
        case .last1h: return "Last 1 h, top 20 apps"
        }
    }

    public var seconds: Double {
        switch self {
        case .last15min: return 900
        case .off: return 0
        case .last1h: return 3600
        }
    }
}
