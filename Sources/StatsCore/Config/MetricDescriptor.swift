import Foundation

// Model layer: static facts about each metric kind (names, chart shape, series, value options).

public enum ChartStyle: String, Sendable {
    /// Series stacked from zero (CPU, memory).
    case stacked
    /// First series above the middle line, second below (network, disk I/O).
    case mirror
    /// One filled series (GPU, disk usage).
    case area
}

/// Which color a series uses. `item` means the item's own color setting.
public enum SeriesTint: String, Sendable {
    case item, orange, violet
}

public struct SeriesSpec: Sendable, Equatable {
    public let key: String
    public let name: String
    public let tint: SeriesTint
}

public struct MetricDescriptor: Sendable {
    public let kind: MetricKind
    public let name: String
    public let label: String
    public let chartStyle: ChartStyle
    /// Series in drawing order. For stacked charts the first series is at the bottom.
    public let series: [SeriesSpec]
    /// Options for "Value shown". The first one is the default.
    public let valueOptions: [String]
    public let defaultMode: DisplayMode
    public let defaultSummary: SummaryStyle
    public let defaultRange: ChartRange
    public let defaultColor: ItemColor
    /// Whether the user can add more than one item of this kind (one per interface or volume).
    public let allowsCopies: Bool

    public static func of(_ kind: MetricKind) -> MetricDescriptor {
        switch kind {
        case .cpu:
            return MetricDescriptor(
                kind: .cpu, name: "CPU", label: "CPU", chartStyle: .stacked,
                series: [SeriesSpec(key: "sys", name: "System", tint: .orange),
                         SeriesSpec(key: "usr", name: "User", tint: .item)],
                valueOptions: ["Total", "User only", "Busiest core"],
                defaultMode: .chartAndNumber, defaultSummary: .valueAndChart, defaultRange: .m5,
                defaultColor: .blue, allowsCopies: false)
        case .memory:
            return MetricDescriptor(
                kind: .memory, name: "Memory", label: "MEM", chartStyle: .stacked,
                series: [SeriesSpec(key: "wired", name: "Wired", tint: .violet),
                         SeriesSpec(key: "app", name: "App", tint: .item),
                         SeriesSpec(key: "comp", name: "Compressed", tint: .orange)],
                valueOptions: ["Used %", "Used GB", "Pressure"],
                defaultMode: .gauge, defaultSummary: .valueAndChart, defaultRange: .h1,
                defaultColor: .blue, allowsCopies: false)
        case .network:
            return MetricDescriptor(
                kind: .network, name: "Network", label: "NET", chartStyle: .mirror,
                series: [SeriesSpec(key: "down", name: "Download", tint: .item),
                         SeriesSpec(key: "up", name: "Upload", tint: .orange)],
                valueOptions: ["Up and down", "Download only", "Upload only"],
                defaultMode: .twoValues, defaultSummary: .twoValues, defaultRange: .m5,
                defaultColor: .blue, allowsCopies: true)
        case .gpu:
            return MetricDescriptor(
                kind: .gpu, name: "GPU", label: "GPU", chartStyle: .area,
                series: [SeriesSpec(key: "dev", name: "Device utilization", tint: .item)],
                valueOptions: ["Device utilization", "Renderer", "Memory in use"],
                defaultMode: .chart, defaultSummary: .valueAndChart, defaultRange: .m15,
                defaultColor: .violet, allowsCopies: false)
        case .diskIO:
            return MetricDescriptor(
                kind: .diskIO, name: "Disk I/O", label: "I/O", chartStyle: .mirror,
                series: [SeriesSpec(key: "rd", name: "Read", tint: .item),
                         SeriesSpec(key: "wr", name: "Write", tint: .orange)],
                valueOptions: ["Read and write", "Total"],
                defaultMode: .twoValues, defaultSummary: .twoValues, defaultRange: .m5,
                defaultColor: .blue, allowsCopies: false)
        case .diskUsage:
            return MetricDescriptor(
                kind: .diskUsage, name: "Disk usage", label: "SSD", chartStyle: .area,
                series: [SeriesSpec(key: "used", name: "Used", tint: .item)],
                valueOptions: ["Free space", "Used %", "Used / total"],
                defaultMode: .number, defaultSummary: .valueAndChart, defaultRange: .d7,
                defaultColor: .blue, allowsCopies: true)
        }
    }
}
