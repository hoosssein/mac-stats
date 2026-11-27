import Foundation

// Model layer: content of the breakdown panels (rows with ›). See docs/kb/product-spec.md section 5.

public struct ListRow: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var sub: String?
    public var value: String
    /// Key in the per-app spark store (nil = no sparkline).
    public var sparkKey: String?

    public init(id: String, name: String, sub: String? = nil, value: String, sparkKey: String? = nil) {
        self.id = id; self.name = name; self.sub = sub; self.value = value; self.sparkKey = sparkKey
    }
}

public struct BarRow: Sendable, Equatable, Identifiable {
    public var id: String
    public var label: String
    /// 0–1. Over 0.65 draws in warning color, over 0.85 in critical color.
    public var fraction: Double
    public var text: String

    public init(id: String, label: String, fraction: Double, text: String) {
        self.id = id; self.label = label; self.fraction = fraction; self.text = text
    }
}

public struct BarGroup: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var rows: [BarRow]

    public init(name: String, rows: [BarRow]) { self.name = name; self.rows = rows }
}

public struct KeyValue: Sendable, Equatable, Identifiable {
    public var id: String { key }
    public var key: String
    public var value: String

    public init(_ key: String, _ value: String) { self.key = key; self.value = value }
}

public enum BreakdownAction: String, Sendable, Equatable {
    case scanFolders, cancelScan
}

public struct BreakdownModel: Sendable, Equatable {
    public enum Content: Sendable, Equatable {
        case list([ListRow])
        case bars([BarGroup])
        case keyValue([KeyValue])
    }

    public var title: String
    public var subtitle: String
    public var content: Content
    /// History series to draw as a small chart above key-value lines, and its period.
    public var chartKey: String?
    public var chartRange: ChartRange = .h1
    public var chartMax: Double?
    public var moreCount = 0
    public var emptyText: String?
    public var note: String?
    public var action: BreakdownAction?
    /// The label size for bar rows ("P1" is short, volume names are long).
    public var wideLabels = false

    public init(title: String, subtitle: String, content: Content) {
        self.title = title; self.subtitle = subtitle; self.content = content
    }
}

public struct BreakdownPresenter: Sendable {
    public let item: ItemConfig
    public let state: LiveState
    public let fmt: UnitFormatter
    public let history: HistoryStore
    public let now: Double
    public let folders: FolderScanState
    public let sampleSeconds: Double

    public init(item: ItemConfig, state: LiveState, units: Units, history: HistoryStore, now: Double,
                folders: FolderScanState = FolderScanState(), sampleSeconds: Double = 2) {
        self.item = item; self.state = state; self.fmt = UnitFormatter(units: units)
        self.history = history; self.now = now; self.folders = folders; self.sampleSeconds = sampleSeconds
    }

    private func key(_ series: String) -> String { HistoryStore.key(item: item.id, series: series) }

    private var waiting: String { "Collecting…" }

    public func model(_ kind: BreakdownKind) -> BreakdownModel {
        switch kind {
        case .perCore: return perCore
        case .cpuProcesses: return processes(by: .cpu)
        case .loadAverage: return loadAverage
        case .cpuSensors: return cpuSensors
        case .memoryPressure: return memoryPressure
        case .memoryProcesses: return processes(by: .memory)
        case .swap: return swap
        case .interfaces: return interfaces
        case .netApps: return netApps
        case .netTotals: return netTotals
        case .publicIP: return publicIP
        case .gpuApps: return gpuApps
        case .gpuMemory: return gpuMemory
        case .perDisk: return perDisk
        case .diskProcesses: return processes(by: .disk)
        case .diskOperations: return diskOperations
        case .volumes: return volumes
        case .largestFolders: return largestFolders
        case .diskTrend: return diskTrend
        }
    }

    /// Cuts a list to the item's "Rows in breakdown panels" and sets the "+ N more" count.
    private func limited(_ m: BreakdownModel) -> BreakdownModel {
        let limit = max(1, item.breakdownRows)
        guard case .list(let rows) = m.content, rows.count > limit else { return m }
        var out = m
        out.content = .list(Array(rows.prefix(limit)))
        out.moreCount = rows.count - limit
        return out
    }

    // MARK: CPU

    private var perCore: BreakdownModel {
        guard let c = state.cpu else {
            var m = BreakdownModel(title: "Per core", subtitle: "% busy", content: .bars([]))
            m.emptyText = waiting
            return m
        }
        let bar = { (core: CoreLoad) in BarRow(id: core.name, label: core.name, fraction: core.usage / 100, text: fmt.percent(core.usage)) }
        var groups: [BarGroup] = []
        let p = c.cores.filter(\.isPerformance), e = c.cores.filter { !$0.isPerformance }
        if !p.isEmpty && !e.isEmpty {
            groups = [BarGroup(name: "Performance cores", rows: p.map(bar)), BarGroup(name: "Efficiency cores", rows: e.map(bar))]
        } else {
            groups = [BarGroup(name: "Cores", rows: c.cores.map(bar))]
        }
        return BreakdownModel(title: "Per core", subtitle: "% busy, last \(Int(sampleSeconds)) s", content: .bars(groups))
    }

    private enum ProcessSort { case cpu, memory, disk }

    private func processes(by sort: ProcessSort) -> BreakdownModel {
        let title = "Top processes"
        let subtitle: String
        switch sort {
        case .cpu: subtitle = "by CPU · % of one core · last \(Int(sampleSeconds)) s"
        case .memory: subtitle = "by memory footprint"
        case .disk: subtitle = "bytes read + written · last \(Int(sampleSeconds)) s"
        }
        guard let snap = state.processes else {
            var m = BreakdownModel(title: title, subtitle: subtitle, content: .list([]))
            m.emptyText = waiting
            return m
        }
        var rows: [ListRow]
        switch sort {
        case .cpu:
            var entries: [(Double, ListRow)] = snap.processes.filter { $0.cpu >= 0.05 }.map {
                ($0.cpu, ListRow(id: "\($0.pid)", name: $0.name, value: fmt.processPercent($0.cpu), sparkKey: "cpu:\($0.name)"))
            }
            if snap.otherCPU >= 0.5 {
                entries.append((snap.otherCPU, ListRow(id: "other", name: "System and other users",
                                                       sub: "processes we cannot measure",
                                                       value: fmt.processPercent(snap.otherCPU))))
            }
            rows = entries.sorted { $0.0 > $1.0 }.map { $0.1 }
        case .memory:
            rows = snap.processes.sorted { $0.memory > $1.memory }.map {
                ListRow(id: "\($0.pid)", name: $0.name, value: fmt.bytes($0.memory), sparkKey: "mem:\($0.name)")
            }
        case .disk:
            rows = snap.processes.filter { $0.readBps + $0.writeBps > 0 }
                .sorted { ($0.readBps + $0.writeBps) > ($1.readBps + $1.writeBps) }.map {
                    let v = $0.readBps >= $0.writeBps ? "R " + fmt.rate($0.readBps) : "W " + fmt.rate($0.writeBps)
                    return ListRow(id: "\($0.pid)", name: $0.name, value: v, sparkKey: "disk:\($0.name)")
                }
        }
        var m = BreakdownModel(title: title, subtitle: subtitle, content: .list(rows))
        if rows.isEmpty { m.emptyText = "Nothing to show right now." }
        m.note = sort == .cpu
            ? "Processes owned by other users (root) cannot be measured one by one. They are shown together as one line."
            : "Processes owned by other users (root) are not included."
        return limited(m)
    }

    private var loadAverage: BreakdownModel {
        guard let c = state.cpu else {
            var m = BreakdownModel(title: "Load average", subtitle: "runnable threads", content: .keyValue([]))
            m.emptyText = waiting
            return m
        }
        var m = BreakdownModel(title: "Load average", subtitle: "runnable threads, last 1 h", content: .keyValue([
            KeyValue("1 min", String(format: "%.2f", c.load1)),
            KeyValue("5 min", String(format: "%.2f", c.load5)),
            KeyValue("15 min", String(format: "%.2f", c.load15)),
            KeyValue("Processes", fmt.count(Double(c.processCount))),
            KeyValue("Threads", c.threadCount > 0 ? fmt.count(Double(c.threadCount)) : "–"),
            KeyValue("Uptime", TimeLabels.duration(c.uptime)),
        ]))
        m.chartKey = key("load")
        return m
    }

    private var cpuSensors: BreakdownModel {
        var m = BreakdownModel(title: "Temperature and clock", subtitle: "optional add-on",
                               content: .keyValue([KeyValue("Status", "Not in version 1")]))
        m.note = "Needs private SMC and IOReport access. Planned as an opt-in add-on, not part of version 1."
        return m
    }

    // MARK: Memory

    private var memoryPressure: BreakdownModel {
        guard let mem = state.memory else {
            var m = BreakdownModel(title: "Memory pressure", subtitle: "last 1 h", content: .keyValue([]))
            m.emptyText = waiting
            return m
        }
        var kv: [KeyValue] = []
        let now = mem.pressurePercent.map { fmt.percent($0) + " · " } ?? ""
        kv.append(KeyValue("Now", now + mem.pressure.title.lowercased()))
        if let peak = history.points(key("pressure"), range: .h1, now: self.now).map(\.max).max() {
            kv.append(KeyValue("Peak (1 h)", fmt.percent(peak)))
        }
        kv.append(KeyValue("Page-ins", fmt.count(mem.pageIns)))
        kv.append(KeyValue("Page-outs", fmt.count(mem.pageOuts)))
        var m = BreakdownModel(title: "Memory pressure", subtitle: "last 1 h · green / yellow / red", content: .keyValue(kv))
        m.chartKey = mem.pressurePercent == nil ? nil : key("pressure")
        m.chartMax = 100
        m.note = "Uses the same three levels as Activity Monitor."
        return m
    }

    private var swap: BreakdownModel {
        guard let mem = state.memory else {
            var m = BreakdownModel(title: "Swap", subtitle: "memory written to disk", content: .keyValue([]))
            m.emptyText = waiting
            return m
        }
        return BreakdownModel(title: "Swap", subtitle: "memory written to disk", content: .keyValue([
            KeyValue("Used", "\(fmt.bytes(mem.swapUsed)) of \(fmt.bytes(mem.swapTotal))"),
            KeyValue("Swap-ins", fmt.count(mem.swapIns)),
            KeyValue("Swap-outs", fmt.count(mem.swapOuts)),
            KeyValue("Compressions", fmt.count(mem.compressions)),
            KeyValue("Decompressions", fmt.count(mem.decompressions)),
        ]))
    }

    // MARK: Network

    private var interfaces: BreakdownModel {
        guard let n = state.network else {
            var m = BreakdownModel(title: "Interfaces", subtitle: "live rate per interface", content: .list([]))
            m.emptyText = waiting
            return m
        }
        let rows = n.interfaces.sorted { ($0.downBps + $0.upBps) > ($1.downBps + $1.upBps) }.map { i -> ListRow in
            var sub = [i.bsdName]
            if let ip = i.ipv4 { sub.append(ip) }
            if i.linkBitsPerSecond > 0 { sub.append(fmt.count(i.linkBitsPerSecond / 1e6) + " Mbps") }
            return ListRow(id: i.bsdName, name: i.displayName, sub: sub.joined(separator: " · "),
                           value: fmt.rate(i.downBps + i.upBps, network: true), sparkKey: "if:\(i.bsdName)")
        }
        var m = BreakdownModel(title: "Interfaces", subtitle: "live rate per interface", content: .list(rows))
        if rows.isEmpty { m.emptyText = "No active interfaces." }
        return limited(m)
    }

    private var netApps: BreakdownModel {
        var m = BreakdownModel(title: "Top apps", subtitle: "download + upload · last 1 s", content: .list([]))
        m.note = "Comes from nettop. It runs only while this panel is open."
        if !state.netAppsAvailable { m.emptyText = "Not available on this Mac."; return m }
        guard let apps = state.netApps else { m.emptyText = waiting; return m }
        let rows = apps.sorted { ($0.downBps + $0.upBps) > ($1.downBps + $1.upBps) }.map { a -> ListRow in
            let v = a.downBps >= a.upBps ? "↓ " + fmt.rate(a.downBps, network: true) : "↑ " + fmt.rate(a.upBps, network: true)
            return ListRow(id: a.name, name: a.name, value: v, sparkKey: "net:\(a.name)")
        }
        m.content = .list(rows)
        if rows.isEmpty { m.emptyText = "No app is using the network right now." }
        return limited(m)
    }

    private var netTotals: BreakdownModel {
        guard let n = state.network else {
            var m = BreakdownModel(title: "Totals", subtitle: "since midnight and since boot", content: .keyValue([]))
            m.emptyText = waiting
            return m
        }
        let boot = n.totalsSinceBoot
        var kv = [
            KeyValue("Downloaded today", fmt.bytes(n.todayIn)),
            KeyValue("Uploaded today", fmt.bytes(n.todayOut)),
            KeyValue("Since boot", "↓ \(fmt.bytes(boot.down)) · ↑ \(fmt.bytes(boot.up))"),
        ]
        if n.peakToday > 0 {
            kv.append(KeyValue("Peak today", fmt.rate(n.peakToday, network: true) + " at " +
                               TimeLabels.clock(Date(timeIntervalSince1970: n.peakTodayAt))))
        }
        var m = BreakdownModel(title: "Totals", subtitle: "since midnight and since boot", content: .keyValue(kv))
        m.note = "Today's totals count while Mac Stats runs."
        return m
    }

    private var publicIP: BreakdownModel {
        let local = state.network?.interfaces.first { $0.ipv4 != nil && $0.bsdName.hasPrefix("en") }?.ipv4
            ?? state.network?.interfaces.first { $0.ipv4 != nil }?.ipv4
        var m = BreakdownModel(title: "Public IP", subtitle: "off", content: .keyValue([
            KeyValue("Local", local ?? "–"),
            KeyValue("Public", "not in version 0.1.0"),
        ]))
        m.note = "Finding the public IP asks an outside web service. Mac Stats makes no network requests, so this stays off."
        return m
    }

    // MARK: GPU

    private var gpuApps: BreakdownModel {
        var m = BreakdownModel(title: "Top apps", subtitle: "share of GPU time · last 2 s", content: .list([]))
        m.note = "Per-app GPU time comes from undocumented IORegistry keys. It is experimental and hides itself if the keys are missing."
        guard let apps = state.gpuApps else { m.emptyText = waiting; return m }
        let rows = apps.filter { $0.share >= 0.5 }.sorted { $0.share > $1.share }.map {
            ListRow(id: "\($0.pid)", name: $0.name, value: fmt.percent($0.share), sparkKey: "gpu:\($0.name)")
        }
        m.content = .list(rows)
        if apps.isEmpty { m.emptyText = "Not available on this Mac." } else if rows.isEmpty { m.emptyText = "No app is using the GPU right now." }
        return limited(m)
    }

    private var gpuMemory: BreakdownModel {
        guard let g = state.gpu else {
            var m = BreakdownModel(title: "GPU memory", subtitle: "memory used by the GPU", content: .keyValue([]))
            m.emptyText = "Not available on this Mac."
            return m
        }
        var kv: [KeyValue] = [KeyValue("In use", g.memoryInUse.map(fmt.bytes) ?? "–"),
                              KeyValue("Allocated", g.memoryAllocated.map(fmt.bytes) ?? "–")]
        if let peak = history.points(key("mem"), range: .m15, now: now).map(\.max).max() {
            kv.append(KeyValue("Peak (15 min)", fmt.bytes(peak)))
        }
        var m = BreakdownModel(title: "GPU memory", subtitle: "unified memory used by the GPU", content: .keyValue(kv))
        m.chartKey = g.memoryInUse == nil ? nil : key("mem")
        m.chartRange = .m15
        return m
    }

    // MARK: Disk I/O

    private var perDisk: BreakdownModel {
        guard let d = state.diskIO else {
            var m = BreakdownModel(title: "Per disk", subtitle: "physical disks · live", content: .list([]))
            m.emptyText = waiting
            return m
        }
        let rows = d.disks.map {
            ListRow(id: $0.name, name: $0.name,
                    sub: "\($0.detail) · R \(fmt.rate($0.readBps)) · W \(fmt.rate($0.writeBps))",
                    value: fmt.rate($0.readBps + $0.writeBps), sparkKey: "dsk:\($0.name)")
        }
        var m = BreakdownModel(title: "Per disk", subtitle: "physical disks · live", content: .list(rows))
        if rows.isEmpty { m.emptyText = "No disks found." }
        return limited(m)
    }

    private var diskOperations: BreakdownModel {
        guard let d = state.diskIO else {
            var m = BreakdownModel(title: "Operations", subtitle: "per second · all disks", content: .keyValue([]))
            m.emptyText = waiting
            return m
        }
        return BreakdownModel(title: "Operations", subtitle: "per second · all disks", content: .keyValue([
            KeyValue("Reads", fmt.count(d.readOps) + " /s"),
            KeyValue("Writes", fmt.count(d.writeOps) + " /s"),
            KeyValue("Avg read latency", String(format: "%.2f ms", d.readLatencyMs)),
            KeyValue("Avg write latency", String(format: "%.2f ms", d.writeLatencyMs)),
        ]))
    }

    // MARK: Disk usage

    private var volumes: BreakdownModel {
        guard let u = state.diskUsage, !u.volumes.isEmpty else {
            var m = BreakdownModel(title: "Volumes", subtitle: "used / total", content: .bars([]))
            m.emptyText = waiting
            return m
        }
        let row = { (v: VolumeStat) in
            BarRow(id: v.path, label: v.name, fraction: v.total > 0 ? v.used / v.total : 0,
                   text: "\(fmt.bytes(v.used)) / \(fmt.bytes(v.total))")
        }
        var groups: [BarGroup] = []
        let internalVols = u.volumes.filter(\.isInternal), externalVols = u.volumes.filter { !$0.isInternal }
        if !internalVols.isEmpty { groups.append(BarGroup(name: "Internal", rows: internalVols.map(row))) }
        if !externalVols.isEmpty { groups.append(BarGroup(name: "External", rows: externalVols.map(row))) }
        var m = BreakdownModel(title: "Volumes", subtitle: "used / total", content: .bars(groups))
        m.wideLabels = true
        return m
    }

    private var largestFolders: BreakdownModel {
        var sub = "scan on request"
        if folders.isRunning { sub = "scanning…" } else if let at = folders.finishedAt {
            sub = "last scan " + TimeLabels.clock(Date(timeIntervalSince1970: at))
            if let d = folders.duration { sub += " · took \(Int(d.rounded())) s" }
        }
        let rows = folders.results.sorted { $0.bytes > $1.bytes }.map {
            ListRow(id: $0.path, name: $0.name, value: fmt.bytes($0.bytes))
        }
        var m = BreakdownModel(title: "Largest folders", subtitle: sub, content: .list(rows))
        m.action = folders.isRunning ? .cancelScan : .scanFolders
        if rows.isEmpty { m.emptyText = folders.isRunning ? "Scanning your folders…" : "Click Scan to measure your largest folders." }
        m.note = "Scanned only when you ask. Needs Full Disk Access to look inside other apps' data."
        return limited(m)
    }

    private var diskTrend: BreakdownModel {
        let presenter = ItemPresenter(item: item, state: state, units: fmt.units, history: history, now: now)
        var kv: [KeyValue] = []
        if let perDay = presenter.trendPerDay {
            kv.append(KeyValue("Change per day", (perDay >= 0 ? "+" : "−") + fmt.bytes(abs(perDay))))
            if perDay > 0, let v = state.diskUsage?.volume(for: item.target) {
                kv.append(KeyValue("Full in", "~\(Int((v.available / perDay).rounded())) days"))
            }
            let pts = history.points(key("used"), range: .d7, now: now, maxPoints: 168)
            var jump = 0.0, at = 0.0
            for (a, b) in zip(pts, pts.dropFirst()) where b.avg - a.avg > jump { jump = b.avg - a.avg; at = b.t }
            if jump > 0 {
                let d = Date(timeIntervalSince1970: at)
                kv.append(KeyValue("Biggest jump", "+" + fmt.bytes(jump) + " · " + TimeLabels.when(d, range: .d7, now: Date(timeIntervalSince1970: now))))
            }
        } else {
            kv.append(KeyValue("Change per day", "needs 1 h of history"))
        }
        kv.append(KeyValue("Checked every", "10 min"))
        var m = BreakdownModel(title: "Trend", subtitle: "last 7 days", content: .keyValue(kv))
        m.chartKey = key("used")
        m.chartRange = .d7
        m.chartMax = presenter.chartMax
        return m
    }
}
