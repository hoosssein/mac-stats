import AppKit
import Observation
import ServiceManagement
import StatsCore
import StatsKit
import SwiftUI

/// One series of a chart: its spec and its points.
struct ChartSeries: Identifiable {
    var id: String { spec.key }
    let spec: SeriesSpec
    let points: [ChartPoint]
}

/// UI layer (state): the app's single source of state. Owns the config, live values, history and the
/// sampling loop. Views read it; changes go through `update(_:)` so side effects (save, appearance,
/// history settings, menu bar) always run.
@MainActor
@Observable
final class AppModel {
    private(set) var config: AppConfig
    private(set) var live = LiveState()
    private(set) var history: HistoryStore
    private(set) var sparks: [String: AppSparkStore] = [:]
    private(set) var folderScan = FolderScanState()
    private(set) var now: Double = Date().timeIntervalSince1970
    private(set) var historyFileSize: Double = 0
    var optionKeyDown = false
    var screenLocked = false
    /// Breakdown panels that are open right now (set by the panel controller).
    private(set) var openBreakdowns: Set<BreakdownKind> = []

    @ObservationIgnored private let store = ConfigStore()
    @ObservationIgnored private let sampler = Sampler()
    @ObservationIgnored private let netTop = NetTopSampler()
    @ObservationIgnored let database = HistoryDatabase()
    @ObservationIgnored private let folderScanner = FolderScan()
    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var netTopTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var forceDiskUsage = true
    @ObservationIgnored private var lastSaved: [Int: Double] = [:]
    @ObservationIgnored private var lastHistorySave: Double = 0
    @ObservationIgnored private var threadCount = 0
    @ObservationIgnored private var onBattery = false
    @ObservationIgnored private var batteryCheckedAt: Double = 0
    /// Called after every config change with the old and new config.
    @ObservationIgnored var onConfigChange: ((AppConfig, AppConfig) -> Void)?
    /// Called after each sampling round.
    @ObservationIgnored var onTick: (() -> Void)?

    init() {
        let c = ConfigStore().load()
        config = c
        history = HistoryStore(keepDays: c.history.keepDays)
    }

    // MARK: Config

    var units: Units { config.general.units }

    func update(_ change: (inout AppConfig) -> Void) {
        let old = config
        var next = config
        change(&next)
        guard next != old else { return }
        config = next
        if next.history.keepDays != old.history.keepDays { history.setKeepDays(next.history.keepDays) }
        if next.history.perAppHistory != old.history.perAppHistory { sparks.removeAll() }
        if next.general.appearance != old.general.appearance { applyAppearance() }
        if next.general.openAtLogin != old.general.openAtLogin { applyLoginItem() }
        scheduleSave()
        onConfigChange?(old, next)
    }

    /// A binding that writes through `update(_:)`.
    func binding<T>(_ path: WritableKeyPath<AppConfig, T>) -> Binding<T> {
        Binding(get: { self.config[keyPath: path] }, set: { v in self.update { $0[keyPath: path] = v } })
    }

    func itemBinding<T>(_ id: String, _ path: WritableKeyPath<ItemConfig, T>, fallback: T) -> Binding<T> {
        Binding(get: { self.config.item(id: id)?[keyPath: path] ?? fallback },
                set: { v in self.update { c in
                    if let i = c.index(of: id) { c.items[i][keyPath: path] = v }
                } })
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = config
        let store = self.store
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            try? store.save(snapshot)
        }
    }

    func replaceConfig(_ c: AppConfig) { update { $0 = c } }

    func applyAppearance() {
        switch config.general.appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    func applyLoginItem() {
        // Only an app bundle can register itself as a login item.
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return }
        let service = SMAppService.mainApp
        do {
            if config.general.openAtLogin {
                if service.status != .enabled { try service.register() }
            } else if service.status == .enabled {
                try service.unregister()
            }
        } catch {
            NSLog("Mac Stats: login item change failed: \(error.localizedDescription)")
        }
    }

    // MARK: Presenters and chart data

    func presenter(_ item: ItemConfig) -> ItemPresenter {
        ItemPresenter(item: item, state: live, units: units, history: history, now: now)
    }

    func breakdown(_ item: ItemConfig, _ kind: BreakdownKind) -> BreakdownModel {
        let interval = kind.needsProcesses ? 2.0 : Double(item.sampleSeconds)
        return BreakdownPresenter(item: item, state: live, units: units, history: history, now: now,
                                  folders: folderScan, sampleSeconds: interval).model(kind)
    }

    func chartSeries(_ item: ItemConfig, range: ChartRange) -> [ChartSeries] {
        item.descriptor.series.map {
            ChartSeries(spec: $0, points: history.points(HistoryStore.key(item: item.id, series: $0.key), range: range, now: now))
        }
    }

    func points(_ key: String, range: ChartRange) -> [ChartPoint] { history.points(key, range: range, now: now) }

    /// Values for the menu bar sparkline: one per second for the chart window.
    func spark(_ item: ItemConfig) -> [Double] {
        history.recent(HistoryStore.key(item: item.id, series: "main"), count: item.menuBarChartSeconds)
    }

    func appSpark(_ key: String?) -> [Double] {
        guard let key, let colon = key.firstIndex(of: ":") else { return [] }
        return sparks[String(key[..<colon])]?.series(String(key[key.index(after: colon)...])) ?? []
    }

    // MARK: Panels

    func setOpenBreakdowns(_ kinds: Set<BreakdownKind>) {
        guard kinds != openBreakdowns else { return }
        openBreakdowns = kinds
        if kinds.contains(.netApps) {
            if netTopTask == nil {
                netTopTask = Task { [weak self] in
                    while !Task.isCancelled {
                        guard let netTop = self?.netTop else { return }
                        let apps = await netTop.sample()
                        guard !Task.isCancelled, let self else { return }
                        self.live.netApps = apps
                        self.recordSparks("net", Dictionary(apps.map { ($0.name, $0.downBps + $0.upBps) }, uniquingKeysWith: +))
                    }
                }
            }
        } else {
            netTopTask?.cancel()
            netTopTask = nil
            live.netApps = nil
        }
        if !kinds.contains(.gpuApps) { live.gpuApps = nil }
    }

    /// A menu opened: refresh disk usage on the next round.
    func panelOpened() { forceDiskUsage = true }

    func startFolderScan() {
        guard !folderScan.isRunning else { return }
        folderScan.isRunning = true
        folderScan.results = []
        let started = Date()
        Task { [weak self] in
            guard let scanner = self?.folderScanner else { return }
            let results = await scanner.run { partial in
                Task { @MainActor [weak self] in
                    if self?.folderScan.isRunning == true { self?.folderScan.results = partial }
                }
            }
            guard let self else { return }
            self.folderScan.results = results
            self.folderScan.isRunning = false
            self.folderScan.finishedAt = Date().timeIntervalSince1970
            self.folderScan.duration = Date().timeIntervalSince(started)
        }
    }

    func cancelFolderScan() { folderScanner.cancel() }

    // MARK: Sampling loop

    func start() {
        applyAppearance()
        applyLoginItem()
        loopTask = Task { [weak self] in
            await self?.loadHistory()
            while !Task.isCancelled {
                await self?.sampleOnce()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func loadHistory() async {
        await database.prune(now: Date().timeIntervalSince1970, keepDays: config.history.keepDays)
        let rows = await database.load()
        var grouped: [String: [Int: [Bucket]]] = [:]
        for r in rows { grouped[r.key, default: [:]][r.tier, default: []].append(r.bucket) }
        for (key, tiers) in grouped {
            for (tier, buckets) in tiers {
                history.restore(key: key, tier: tier, buckets: buckets)
                lastSaved[tier] = max(lastSaved[tier] ?? 0, buckets.last?.t ?? 0)
            }
        }
        historyFileSize = await database.fileSize()
    }

    private func makeRequest() -> Sampler.Request {
        let t = Date().timeIntervalSince1970
        if t - batteryCheckedAt > 30 { onBattery = SystemState.onBattery; batteryCheckedAt = t }
        var intervals: [MetricKind: Double] = [:]
        for item in config.items {
            let s = onBattery ? config.general.onBattery.seconds(onPower: item.sampleSeconds) : item.sampleSeconds
            intervals[item.kind] = min(intervals[item.kind] ?? .infinity, Double(s))
        }
        if intervals[.diskUsage] != nil { intervals[.diskUsage] = 600 }
        // CPU totals are needed to compute "System and other users".
        let processPanel = openBreakdowns.contains { $0.needsProcesses }
        let processInterval: Double? = processPanel ? 2 : (config.history.perAppHistory == .off ? nil : 5)
        if processInterval != nil, intervals[.cpu] == nil { intervals[.cpu] = 1 }
        let force = forceDiskUsage
        forceDiskUsage = false
        return Sampler.Request(intervals: intervals, processInterval: processInterval,
                               gpuApps: openBreakdowns.contains(.gpuApps), forceDiskUsage: force)
    }

    private func sampleOnce() async {
        let result = await sampler.sample(makeRequest())
        apply(result)
        onTick?()
    }

    private func apply(_ r: SampleResult) {
        now = r.time
        if let t = r.threadCount { threadCount = t }
        if var c = r.cpu { c.threadCount = threadCount; live.cpu = c }
        if let m = r.memory { live.memory = m }
        if let n = r.network { live.network = n }
        if let g = r.gpu { live.gpu = g }
        if let d = r.diskIO { live.diskIO = d }
        if let u = r.diskUsage { live.diskUsage = u }
        if let p = r.processes {
            live.processes = p
            recordSparks("cpu", Dictionary(p.processes.map { ($0.name, $0.cpu) }, uniquingKeysWith: +))
            recordSparks("mem", Dictionary(p.processes.map { ($0.name, $0.memory) }, uniquingKeysWith: max))
            recordSparks("disk", Dictionary(p.processes.map { ($0.name, $0.readBps + $0.writeBps) }, uniquingKeysWith: +))
        }
        if openBreakdowns.contains(.gpuApps), let g = r.gpuApps {
            live.gpuApps = g
            recordSparks("gpu", Dictionary(g.map { ($0.name, $0.share) }, uniquingKeysWith: +))
        }
        if let n = r.network {
            recordSparks("if", Dictionary(n.interfaces.map { ($0.bsdName, $0.downBps + $0.upBps) }, uniquingKeysWith: +))
        }
        if let d = r.diskIO {
            recordSparks("dsk", Dictionary(d.disks.map { ($0.name, $0.readBps + $0.writeBps) }, uniquingKeysWith: +))
        }
        live.time = r.time

        let kinds = r.sampledKinds
        var values: [String: Double] = [:]
        for item in config.items where kinds.contains(item.kind) {
            for (k, v) in presenter(item).historyValues { values[HistoryStore.key(item: item.id, series: k)] = v }
        }
        if !values.isEmpty { history.record(values, at: r.time) }
        saveHistoryIfDue()
    }

    private func recordSparks(_ group: String, _ values: [String: Double]) {
        guard config.history.perAppHistory != .off || !openBreakdowns.isEmpty else { return }
        let seconds = max(config.history.perAppHistory.seconds, 120)
        let capacity = Int(seconds / 2)
        if sparks[group]?.capacity != capacity { sparks[group] = AppSparkStore(capacity: capacity) }
        sparks[group]!.record(values, keepTop: 20)
    }

    private func saveHistoryIfDue() {
        guard now - lastHistorySave >= 30 else { return }
        lastHistorySave = now
        var rows: [HistoryDatabase.Row] = []
        var newest = lastSaved
        for (key, series) in history.series {
            for tier in 1..<series.specs.count {
                for b in series.completedBuckets(tier: tier, after: lastSaved[tier] ?? 0) {
                    rows.append(HistoryDatabase.Row(key: key, tier: tier, bucket: b))
                    newest[tier] = max(newest[tier] ?? 0, b.t)
                }
            }
        }
        lastSaved = newest
        let db = database
        let keepDays = config.history.keepDays
        let t = now
        Task { [weak self] in
            await db.save(rows)
            if Int(t) % 3600 < 30 { await db.prune(now: t, keepDays: keepDays) }
            let size = await db.fileSize()
            self?.historyFileSize = size
        }
    }

    func deleteAllHistory() {
        history.removeAll()
        sparks.removeAll()
        lastSaved = [:]
        Task { [weak self] in
            guard let db = self?.database else { return }
            await db.deleteAll()
            let size = await db.fileSize()
            self?.historyFileSize = size
        }
    }
}
