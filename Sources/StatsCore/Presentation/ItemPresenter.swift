import Foundation

// Model layer: turns an item's config and the live numbers into the text the UI shows.
// Row lists follow docs/kb/product-spec.md section 5.

public enum BreakdownKind: String, Sendable, CaseIterable {
    case perCore, cpuProcesses, loadAverage, cpuSensors
    case memoryPressure, memoryProcesses, swap
    case interfaces, netApps, netTotals, publicIP
    case gpuApps, gpuMemory
    case perDisk, diskProcesses, diskOperations
    case volumes, largestFolders, diskTrend

    /// Breakdowns that need per-process sampling while open.
    public var needsProcesses: Bool { [.cpuProcesses, .memoryProcesses, .diskProcesses].contains(self) }
}

public enum PillLevel: String, Sendable, Equatable {
    case ok, warning, critical
}

public struct DetailRow: Sendable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var value: String?
    public var pillLevel: PillLevel?
    public var breakdown: BreakdownKind?
    /// Draw a separator line above this row.
    public var separatorBefore: Bool

    public init(id: String, label: String, value: String?, pillLevel: PillLevel? = nil,
                breakdown: BreakdownKind? = nil, separatorBefore: Bool = false) {
        self.id = id; self.label = label; self.value = value; self.pillLevel = pillLevel
        self.breakdown = breakdown; self.separatorBefore = separatorBefore
    }
}

public struct ItemPresenter: Sendable {
    public let item: ItemConfig
    public let state: LiveState
    public let fmt: UnitFormatter
    public let history: HistoryStore?
    public let now: Double

    public init(item: ItemConfig, state: LiveState, units: Units, history: HistoryStore? = nil, now: Double = 0) {
        self.item = item; self.state = state; self.fmt = UnitFormatter(units: units)
        self.history = history; self.now = now
    }

    public var descriptor: MetricDescriptor { item.descriptor }

    // MARK: Values

    private var volume: VolumeStat? { state.diskUsage?.volume(for: item.target) }
    private var net: (down: Double, up: Double)? { state.network?.rates(target: item.target) }

    /// Whether this item has any data yet.
    public var available: Bool {
        switch item.kind {
        case .cpu: return state.cpu != nil
        case .memory: return state.memory != nil
        case .network: return state.network != nil
        case .gpu: return state.gpu != nil
        case .diskIO: return state.diskIO != nil
        case .diskUsage: return volume != nil
        }
    }

    /// Values to record in history, keyed by series key. Includes "main" (the sparkline value)
    /// and a few extra series used by breakdown charts.
    public var historyValues: [String: Double] {
        switch item.kind {
        case .cpu:
            guard let c = state.cpu else { return [:] }
            return ["sys": c.system, "usr": c.user, "main": c.total, "load": c.load1]
        case .memory:
            guard let m = state.memory else { return [:] }
            var v = ["wired": m.wired, "app": m.app, "comp": m.compressed, "main": m.used]
            if let p = m.pressurePercent { v["pressure"] = p }
            return v
        case .network:
            guard let r = net else { return [:] }
            return ["down": r.down, "up": r.up, "main": r.down]
        case .gpu:
            guard let g = state.gpu else { return [:] }
            var v = ["dev": g.device, "main": g.device]
            if let m = g.memoryInUse { v["mem"] = m }
            return v
        case .diskIO:
            guard let d = state.diskIO else { return [:] }
            return ["rd": d.readBps, "wr": d.writeBps, "main": d.readBps + d.writeBps]
        case .diskUsage:
            guard let v = volume else { return [:] }
            return ["used": v.used, "main": v.used]
        }
    }

    /// The upper end of the chart scale. Nil means "pick a nice value from the data".
    public var chartMax: Double? {
        switch item.kind {
        case .cpu, .gpu: return 100
        case .memory: return state.memory?.total
        case .diskUsage: return volume.map { Scale.niceMax($0.total) }
        case .network, .diskIO: return nil
        }
    }

    /// Fixed maximum for the menu bar sparkline. Nil = scale to the data.
    public var sparkMax: Double? {
        switch item.kind {
        case .cpu, .gpu: return 100
        case .memory: return state.memory?.total
        case .diskUsage: return volume?.total
        case .network, .diskIO: return nil
        }
    }

    /// Scale label text inside charts.
    public func axisLabel(_ v: Double) -> String {
        switch item.kind {
        case .cpu, .gpu: return fmt.axisPercent(v)
        case .memory, .diskUsage: return fmt.axisBytes(v)
        case .network: return fmt.axisRate(v, network: true)
        case .diskIO: return fmt.axisRate(v)
        }
    }

    /// A single value as text, for tooltips.
    public func valueText(_ v: Double) -> String {
        switch item.kind {
        case .cpu, .gpu: return fmt.percent(v)
        case .memory, .diskUsage: return fmt.bytes(v)
        case .network: return fmt.rate(v, network: true)
        case .diskIO: return fmt.rate(v)
        }
    }

    // MARK: Text

    public var bigValue: String {
        guard available else { return "–" }
        switch item.kind {
        case .cpu: return fmt.percent(state.cpu!.total)
        case .memory: return fmt.bytes(state.memory!.used)
        case .network: return "↓ " + fmt.rate(net!.down, network: true)
        case .gpu: return fmt.percent(state.gpu!.device)
        case .diskIO: return fmt.rate(state.diskIO!.readBps + state.diskIO!.writeBps)
        case .diskUsage: return fmt.bytes(volume!.available) + " free"
        }
    }

    public var subLine: String {
        guard available else { return "Not available on this Mac" }
        switch item.kind {
        case .cpu:
            let c = state.cpu!
            let n = c.cores.count
            if c.performanceCores > 0 && c.efficiencyCores > 0 {
                return "\(n) cores · \(c.performanceCores) performance, \(c.efficiencyCores) efficiency"
            }
            return "\(n) cores"
        case .memory:
            let m = state.memory!
            return "of \(fmt.bytes(m.total)) · pressure \(m.pressure.title.lowercased())"
        case .network:
            let name: String
            if let t = item.target {
                name = state.network?.interfaces.first { $0.bsdName == t }.map { "\($0.displayName) (\($0.bsdName))" } ?? t
            } else {
                name = "all interfaces"
            }
            return "↑ " + fmt.rate(net!.up, network: true) + " · " + name
        case .gpu: return state.gpu!.name
        case .diskIO: return "read + write · all disks"
        case .diskUsage:
            let v = volume!
            return "\(v.name) · \(fmt.bytes(v.total))"
        }
    }

    /// Text for Number, Chart + number and Gauge modes, depending on "Value shown".
    public var menuBarText: String {
        guard available else { return "–" }
        switch item.kind {
        case .cpu:
            let c = state.cpu!
            switch item.valueShown {
            case 1: return fmt.percent(c.user)
            case 2: return fmt.percent(c.busiestCore?.usage ?? c.total)
            default: return fmt.percent(c.total)
            }
        case .memory:
            let m = state.memory!
            switch item.valueShown {
            case 1: return fmt.bytes(m.used)
            case 2: return m.pressure.title
            default: return fmt.percent(m.total > 0 ? m.used / m.total * 100 : 0)
            }
        case .network:
            let r = net!
            switch item.valueShown {
            case 1: return "↓ " + fmt.rate(r.down, network: true)
            case 2: return "↑ " + fmt.rate(r.up, network: true)
            default: return "↓ " + fmt.rate(r.down, network: true) + " ↑ " + fmt.rate(r.up, network: true)
            }
        case .gpu:
            let g = state.gpu!
            switch item.valueShown {
            case 1: return fmt.percent(g.renderer)
            case 2: return g.memoryInUse.map(fmt.bytes) ?? "–"
            default: return fmt.percent(g.device)
            }
        case .diskIO:
            let d = state.diskIO!
            if item.valueShown == 1 { return fmt.rate(d.readBps + d.writeBps) }
            return "R " + fmt.rate(d.readBps) + " W " + fmt.rate(d.writeBps)
        case .diskUsage:
            let v = volume!
            switch item.valueShown {
            case 1: return fmt.percent(v.total > 0 ? v.used / v.total * 100 : 0)
            case 2: return fmt.bytes(v.used) + " / " + fmt.bytes(v.total)
            default: return fmt.bytes(v.available)
            }
        }
    }

    /// The two small lines for "Two values" mode.
    public var menuBarTwo: (String, String) {
        guard available else { return ("–", "–") }
        switch item.kind {
        case .cpu: return ("usr " + fmt.percent(state.cpu!.user), "sys " + fmt.percent(state.cpu!.system))
        case .memory: return (fmt.bytes(state.memory!.used), "of " + fmt.bytes(state.memory!.total))
        case .network: return ("↑ " + fmt.rate(net!.up, network: true), "↓ " + fmt.rate(net!.down, network: true))
        case .gpu:
            let g = state.gpu!
            return ("dev " + fmt.percent(g.device), "mem " + (g.memoryInUse.map(fmt.bytes) ?? "–"))
        case .diskIO: return ("R " + fmt.rate(state.diskIO!.readBps), "W " + fmt.rate(state.diskIO!.writeBps))
        case .diskUsage:
            let v = volume!
            return (fmt.bytes(v.available) + " free", fmt.percent(v.total > 0 ? v.used / v.total * 100 : 0) + " used")
        }
    }

    /// Fill level for Gauge mode, 0–1.
    public var gauge: Double {
        guard available else { return 0 }
        let v: Double
        switch item.kind {
        case .cpu: v = state.cpu!.total / 100
        case .memory: v = state.memory!.total > 0 ? state.memory!.used / state.memory!.total : 0
        case .network:
            let link = item.target.flatMap { t in state.network?.interfaces.first { $0.bsdName == t }?.linkBitsPerSecond }
            let cap = (link ?? 0) > 0 ? link! / 8 : 12_500_000
            v = net!.down / cap
        case .gpu: v = state.gpu!.device / 100
        case .diskIO: v = (state.diskIO!.readBps + state.diskIO!.writeBps) / 500_000_000
        case .diskUsage: v = volume!.total > 0 ? volume!.used / volume!.total : 0
        }
        return min(1, max(0, v))
    }

    /// Summary text for a row in the Other metrics list.
    public var summaryText: String {
        if item.summaryStyle == .twoValues {
            let t = menuBarTwo
            return t.0 + " · " + t.1
        }
        return bigValue
    }

    /// Two short "label value" texts for overview cards.
    public var cardDetails: [String] {
        rows.filter { $0.breakdown == nil && $0.value != nil && !$0.label.hasPrefix("Purgeable") }
            .prefix(2).map { "\($0.label) \($0.value!)" }
    }

    // MARK: Rows

    public var rows: [DetailRow] {
        switch item.kind {
        case .cpu: return cpuRows
        case .memory: return memoryRows
        case .network: return networkRows
        case .gpu: return gpuRows
        case .diskIO: return diskIORows
        case .diskUsage: return diskUsageRows
        }
    }

    private var cpuRows: [DetailRow] {
        let c = state.cpu
        let busiest = c?.busiestCore.map { "busiest \($0.name) · \(fmt.percent($0.usage))" }
        let top = state.processes?.processes.max { $0.cpu < $1.cpu }.map { "\($0.name) · \(fmt.percent($0.cpu))" }
        return [
            DetailRow(id: "user", label: "User", value: c.map { fmt.percent($0.user) }),
            DetailRow(id: "system", label: "System", value: c.map { fmt.percent($0.system) }),
            DetailRow(id: "idle", label: "Idle", value: c.map { fmt.percent($0.idle) }),
            DetailRow(id: "cores", label: "Per core", value: busiest, breakdown: .perCore, separatorBefore: true),
            DetailRow(id: "procs", label: "Top processes", value: top, breakdown: .cpuProcesses),
            DetailRow(id: "load", label: "Load average", value: c.map { String(format: "%.2f", $0.load1) }, breakdown: .loadAverage),
            DetailRow(id: "sensors", label: "Temperature and clock", value: "add-on", breakdown: .cpuSensors),
        ]
    }

    private var memoryRows: [DetailRow] {
        let m = state.memory
        let top = state.processes?.processes.max { $0.memory < $1.memory }.map { "\($0.name) · \(fmt.bytes($0.memory))" }
        let level: PillLevel? = m.map { $0.pressure == .normal ? .ok : $0.pressure == .warning ? .warning : .critical }
        return [
            DetailRow(id: "app", label: "App memory", value: m.map { fmt.bytes($0.app) }),
            DetailRow(id: "wired", label: "Wired", value: m.map { fmt.bytes($0.wired) }),
            DetailRow(id: "comp", label: "Compressed", value: m.map { fmt.bytes($0.compressed) }),
            DetailRow(id: "cached", label: "Cached files", value: m.map { fmt.bytes($0.cached) }),
            DetailRow(id: "pressure", label: "Memory pressure", value: m?.pressure.title, pillLevel: level,
                      breakdown: .memoryPressure, separatorBefore: true),
            DetailRow(id: "procs", label: "Top processes", value: top, breakdown: .memoryProcesses),
            DetailRow(id: "swap", label: "Swap", value: m.map { fmt.bytes($0.swapUsed) }, breakdown: .swap),
        ]
    }

    private var networkRows: [DetailRow] {
        let r = net
        let active = state.network?.activeInterfaces.count
        let topApp = state.netApps?.max { ($0.downBps + $0.upBps) < ($1.downBps + $1.upBps) }
            .map { "\($0.name) · \(fmt.rate($0.downBps + $0.upBps, network: true))" }
        return [
            DetailRow(id: "down", label: "Download", value: r.map { fmt.rate($0.down, network: true) }),
            DetailRow(id: "up", label: "Upload", value: r.map { fmt.rate($0.up, network: true) }),
            DetailRow(id: "ifs", label: "Interfaces", value: active.map { "\($0) active" }, breakdown: .interfaces, separatorBefore: true),
            DetailRow(id: "apps", label: "Top apps", value: topApp, breakdown: .netApps),
            DetailRow(id: "totals", label: "Totals today", value: state.network.map { "↓ " + fmt.bytes($0.todayIn) }, breakdown: .netTotals),
            DetailRow(id: "ip", label: "Public IP", value: "off", breakdown: .publicIP),
        ]
    }

    private var gpuRows: [DetailRow] {
        let g = state.gpu
        let topApp = state.gpuApps?.max { $0.share < $1.share }.map { "\($0.name) · \(fmt.percent($0.share))" }
        return [
            DetailRow(id: "dev", label: "Device", value: g.map { fmt.percent($0.device) }),
            DetailRow(id: "ren", label: "Renderer", value: g.map { fmt.percent($0.renderer) }),
            DetailRow(id: "tiler", label: "Tiler", value: g.map { fmt.percent($0.tiler) }),
            DetailRow(id: "apps", label: "Top apps", value: topApp ?? "experimental", breakdown: .gpuApps, separatorBefore: true),
            DetailRow(id: "mem", label: "GPU memory", value: g?.memoryInUse.map(fmt.bytes), breakdown: .gpuMemory),
        ]
    }

    private var diskIORows: [DetailRow] {
        let d = state.diskIO
        let top = state.processes?.processes.max { ($0.readBps + $0.writeBps) < ($1.readBps + $1.writeBps) }
            .map { "\($0.name) · \(fmt.rate($0.readBps + $0.writeBps))" }
        return [
            DetailRow(id: "rd", label: "Read", value: d.map { fmt.rate($0.readBps) }),
            DetailRow(id: "wr", label: "Write", value: d.map { fmt.rate($0.writeBps) }),
            DetailRow(id: "disks", label: "Per disk", value: d.map { "\($0.disks.count) disk\($0.disks.count == 1 ? "" : "s")" },
                      breakdown: .perDisk, separatorBefore: true),
            DetailRow(id: "procs", label: "Top processes", value: top, breakdown: .diskProcesses),
            DetailRow(id: "ops", label: "Operations", value: d.map { fmt.count($0.readOps + $0.writeOps) + " /s" }, breakdown: .diskOperations),
        ]
    }

    private var diskUsageRows: [DetailRow] {
        let v = volume
        let mounted = state.diskUsage?.volumes.count
        let trend = trendPerDay.map { ($0 >= 0 ? "+" : "−") + fmt.bytes(abs($0)) + "/day" }
        return [
            DetailRow(id: "used", label: "Used", value: v.map { fmt.bytes($0.used) }),
            DetailRow(id: "avail", label: "Available", value: v.map { fmt.bytes($0.available) }),
            DetailRow(id: "purge", label: "Purgeable (counted as free)", value: v.map { fmt.bytes($0.purgeable) }),
            DetailRow(id: "vols", label: "Volumes", value: mounted.map { "\($0) mounted" }, breakdown: .volumes, separatorBefore: true),
            DetailRow(id: "folders", label: "Largest folders", value: "scan on request", breakdown: .largestFolders),
            DetailRow(id: "trend", label: "Trend", value: trend ?? "collecting", breakdown: .diskTrend),
        ]
    }

    /// Change in used space per day over the last 7 days (needs at least 1 hour of history).
    public var trendPerDay: Double? {
        guard item.kind == .diskUsage, let history else { return nil }
        let pts = history.points(HistoryStore.key(item: item.id, series: "used"), range: .d7, now: now)
        guard let first = pts.first, let last = pts.last, last.t - first.t >= 3600 else { return nil }
        return (last.avg - first.avg) / ((last.t - first.t) / 86_400)
    }
}
