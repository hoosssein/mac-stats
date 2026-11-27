import Foundation
import XCTest
@testable import StatsCore

final class ConfigTests: XCTestCase {
    // Defaults must match docs/kb/configuration.md section 1.
    func testDefaultItemsMatchKnowledgeBase() {
        let c = AppConfig.default
        XCTAssertEqual(c.items.map(\.id), ["cpu", "mem", "net", "gpu", "dio", "du"])
        XCTAssertEqual(c.items.map(\.kind), [.cpu, .memory, .network, .gpu, .diskIO, .diskUsage])
        XCTAssertEqual(c.items.map(\.showInMenuBar), [true, true, true, false, false, false])
        XCTAssertTrue(c.items.allSatisfy(\.showInMenu))
        XCTAssertEqual(c.items.map(\.displayMode), [.chartAndNumber, .gauge, .twoValues, .chart, .twoValues, .number])
        XCTAssertEqual(c.items.map(\.menuRange), [.m5, .h1, .m5, .m15, .m5, .d7])
        XCTAssertEqual(c.items.map(\.color), [.blue, .blue, .blue, .violet, .blue, .blue])
        XCTAssertEqual(c.items.map(\.summaryStyle), [.valueAndChart, .valueAndChart, .twoValues, .valueAndChart, .twoValues, .valueAndChart])
        XCTAssertEqual(c.items.map(\.label), ["CPU", "MEM", "NET", "GPU", "I/O", "SSD"])
        XCTAssertEqual(c.items.map(\.name), ["CPU", "Memory", "Network", "GPU", "Disk I/O", "Disk usage"])
        XCTAssertTrue(c.items.allSatisfy { $0.showLabel && $0.menuBarChartSeconds == 60 && $0.sampleSeconds == 1 && $0.breakdownRows == 8 && $0.valueShown == 0 })
        XCTAssertNil(c.items[2].target)
        XCTAssertEqual(c.items[5].target, "/")
        XCTAssertFalse(c.showStatsIcon)
        XCTAssertFalse(c.statsIconVisible)
    }

    func testDefaultMenuGeneralHistory() {
        let c = AppConfig.default
        XCTAssertEqual(c.menu.clickOpens, .itemMenu)
        XCTAssertTrue(c.menu.showOtherMetrics)
        XCTAssertEqual(c.menu.listStyle, .compactRows)
        XCTAssertEqual(c.menu.sideMenuOpens, .onHover)
        XCTAssertEqual(c.menu.cardOpens, .beside)
        XCTAssertEqual(c.menu.overviewColumns, 2)
        XCTAssertEqual(c.menu.overviewCard, .full)
        XCTAssertEqual(c.menu.overviewRange, .m15)
        XCTAssertEqual(c.general.appearance, .system)
        XCTAssertEqual(c.general.chartValues, .off)
        XCTAssertEqual(c.general.menuBarChartColor, .colored)
        XCTAssertTrue(c.general.openAtLogin)
        XCTAssertEqual(c.general.onBattery, .every2s)
        XCTAssertEqual(c.general.whenLocked, .pauseDrawing)
        XCTAssertEqual(c.general.units, .base1000)
        XCTAssertEqual(c.history.keepDays, 30)
        XCTAssertEqual(c.history.perAppHistory, .last15min)
    }

    func testStatsIconShowsWhenMenuBarIsEmpty() {
        var c = AppConfig.default
        for i in c.items.indices { c.items[i].showInMenuBar = false }
        XCTAssertTrue(c.statsIconVisible)
        c.items[0].showInMenuBar = true
        XCTAssertFalse(c.statsIconVisible)
        c.showStatsIcon = true
        XCTAssertTrue(c.statsIconVisible)
    }

    func testRoundTripAndLenientDecoding() throws {
        var c = AppConfig.default
        c.menu.overviewColumns = 3
        c.items[0].displayMode = .gauge
        let back = try ConfigStore.decode(ConfigStore.encode(c))
        XCTAssertEqual(back, c)

        let partial = #"{"items":[{"id":"cpu","kind":"cpu","showInMenuBar":false}],"menu":{"overviewColumns":9}}"#
        let p = try ConfigStore.decode(Data(partial.utf8))
        XCTAssertEqual(p.items.count, 1)
        XCTAssertEqual(p.items[0].displayMode, .chartAndNumber)
        XCTAssertFalse(p.items[0].showInMenuBar)
        XCTAssertEqual(p.menu.overviewColumns, 3)
        XCTAssertEqual(p.general, GeneralConfig())
    }

    func testAddMoveRemoveReset() {
        var c = AppConfig.default
        let added = c.add(kind: .diskUsage, target: "/Volumes/T7 Shield", name: "Disk usage · T7", label: "T7")
        XCTAssertFalse(added.showInMenuBar)
        XCTAssertTrue(added.showInMenu)
        XCTAssertEqual(c.items.last?.id, added.id)
        XCTAssertEqual(added.name, "Disk usage · T7")

        c.move(id: added.id, before: "cpu")
        XCTAssertEqual(c.items.first?.id, added.id)
        c.move(id: added.id, by: 1)
        XCTAssertEqual(c.items[1].id, added.id)

        c.remove(id: "cpu")
        XCTAssertNil(c.item(id: "cpu"))
        let back = c.add(kind: .cpu)
        XCTAssertEqual(back.id, "cpu")
        XCTAssertFalse(back.showInMenuBar)

        c.general.appearance = .dark
        c.resetItemsAndMenu()
        XCTAssertEqual(c.items, AppConfig.defaultItems)
        XCTAssertEqual(c.general.appearance, .dark)
    }
}

final class MathTests: XCTestCase {
    func testCounterWraparound() {
        XCTAssertEqual(Counter.delta(10, 25), 15)
        XCTAssertEqual(Counter.delta(UInt64(UInt32.max) - 4, 5, bits: 32), 10)
        XCTAssertEqual(Counter.delta(UInt64.max - 1, 3), 5)
        XCTAssertEqual(Counter.rate(100, seconds: 2), 50)
        XCTAssertEqual(Counter.rate(100, seconds: 0), 0)
    }

    func testCPUUsage() {
        let a = CPUTicks(user: 100, system: 50, idle: 850, nice: 0)
        let b = CPUTicks(user: 130, system: 60, idle: 900, nice: 10)
        let u = CPUUsage.between(a, b)
        XCTAssertEqual(u.user, 40, accuracy: 0.001)
        XCTAssertEqual(u.system, 10, accuracy: 0.001)
        XCTAssertEqual(u.idle, 50, accuracy: 0.001)
        let avg = CPUUsage.average([(a, b), (a, a)])
        XCTAssertEqual(avg.total, 50, accuracy: 0.001)
        XCTAssertEqual(CPUUsage.between(a, a).idle, 100)
    }

    func testNiceMax() {
        XCTAssertEqual(Scale.niceMax(0), 1)
        XCTAssertEqual(Scale.niceMax(0.9), 1)
        XCTAssertEqual(Scale.niceMax(1260), 2000)
        XCTAssertEqual(Scale.niceMax(4100), 5000)
        XCTAssertEqual(Scale.niceMax(9100), 10000)
    }
}

final class FormatTests: XCTestCase {
    let f = UnitFormatter()

    func testWireframeFormats() {
        XCTAssertEqual(f.percent(23.4), "23%")
        XCTAssertEqual(f.bytes(17.04e9), "17.0 GB")
        XCTAssertEqual(f.bytes(412e9), "412 GB")
        XCTAssertEqual(f.bytes(1.38e12), "1.38 TB")
        XCTAssertEqual(f.rate(320e3), "320 KB/s")
        XCTAssertEqual(f.rate(1.2e6), "1.2 MB/s")
        XCTAssertEqual(f.rate(14e6), "14 MB/s")
        XCTAssertEqual(f.processPercent(48.23), "48.2%")
        XCTAssertEqual(f.axisRate(5e6), "5 MB/s")
        XCTAssertEqual(f.axisBytes(32e9), "32 GB")
        XCTAssertEqual(f.axisBytes(1e12), "1 TB")
        XCTAssertEqual(f.axisPercent(50), "50%")
        XCTAssertEqual(f.count(2914), "2,914")
    }

    func testOtherUnits() {
        XCTAssertEqual(UnitFormatter(units: .base1024).bytes(Double(1 << 30) * 2), "2.0 GiB")
        XCTAssertEqual(UnitFormatter(units: .bitsForNetwork).rate(1e6, network: true), "8.0 Mb/s")
        XCTAssertEqual(UnitFormatter(units: .bitsForNetwork).rate(1e6, network: false), "1.0 MB/s")
    }

    func testTimeLabels() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_795_000_000)
        let past = now.addingTimeInterval(-124)
        XCTAssertEqual(TimeLabels.ago(124), "2 min 4 s ago")
        XCTAssertEqual(TimeLabels.ago(0.2), "now")
        XCTAssertEqual(TimeLabels.ago(3 * 86_400 + 4 * 3600), "3 d 4 h ago")
        XCTAssertEqual(TimeLabels.when(past, range: .m5, now: now, calendar: cal).count, 8)
        XCTAssertTrue(TimeLabels.when(now.addingTimeInterval(-3 * 86_400), range: .d7, now: now, calendar: cal).contains(" · "))
        XCTAssertEqual(TimeLabels.duration(6 * 86_400 + 3 * 3600), "6 d 3 h")
    }
}

final class HistoryTests: XCTestCase {
    func testRingBuffer() {
        var r = RingBuffer<Int>(capacity: 3)
        for i in 1...5 { r.append(i) }
        XCTAssertEqual(r.elements, [3, 4, 5])
        XCTAssertEqual(r.last, 5)
        XCTAssertEqual(r.suffix(2), [4, 5])
    }

    func testTiersRollUpMinAvgMax() {
        var s = TieredSeries(keepDays: 7)
        for i in 0..<20 { s.append(Double(i), at: 1000 + Double(i)) }
        XCTAssertEqual(s.buckets(tier: 0).count, 20)
        let t1 = s.buckets(tier: 1)
        XCTAssertEqual(t1.count, 2)
        XCTAssertEqual(t1[0].min, 0)
        XCTAssertEqual(t1[0].max, 9)
        XCTAssertEqual(t1[0].avg, 4.5, accuracy: 0.001)
        XCTAssertEqual(s.latest, 19)
        XCTAssertEqual(s.recent(3), [17, 18, 19])
    }

    func testPointsAreLimitedAndKeepSpikes() {
        var s = TieredSeries()
        for i in 0..<3600 { s.append(i == 1800 ? 100 : 1, at: Double(i)) }
        let pts = s.points(range: .h1, now: 3599, maxPoints: 300)
        XCTAssertLessThanOrEqual(pts.count, 301)
        XCTAssertEqual(pts.map(\.max).max(), 100)
        let small = s.points(range: .m1, now: 3599)
        XCTAssertEqual(small.count, 61)
    }

    func testRestoreAndKeepDays() {
        var h = HistoryStore(keepDays: 30)
        h.record(["cpu.usr": 10], at: 0)
        h.restore(key: "cpu.usr", tier: 1, buckets: [Bucket(t: -100, value: 5)])
        XCTAssertEqual(h.series["cpu.usr"]?.buckets(tier: 1).first?.t, -100)
        h.setKeepDays(7)
        XCTAssertEqual(h.keepDays, 7)
        XCTAssertEqual(h.series["cpu.usr"]?.buckets(tier: 1).count, 2)
        XCTAssertEqual(h.latest("cpu.usr"), 10)
    }

    func testAppSparkStoreDropsStaleApps() {
        var s = AppSparkStore(capacity: 3)
        s.record(["a": 1, "b": 2])
        for _ in 0..<4 { s.record(["b": 2]) }
        XCTAssertTrue(s.series("a").isEmpty)
        XCTAssertEqual(s.series("b").count, 3)
    }
}

final class PresenterTests: XCTestCase {
    func sampleState() -> LiveState {
        var s = LiveState()
        s.cpu = CPUSnapshot(user: 14, system: 9, idle: 77,
                            cores: [CoreLoad(name: "E1", isPerformance: false, usage: 20), CoreLoad(name: "P1", isPerformance: true, usage: 61)],
                            performanceCores: 1, efficiencyCores: 1, load1: 3.42, load5: 2.98, load15: 2.51,
                            processCount: 612, threadCount: 2914, uptime: 6 * 86_400)
        s.memory = MemorySnapshot(total: 32e9, app: 11.2e9, wired: 3.6e9, compressed: 2.1e9, cached: 8.4e9, free: 1e9,
                                  pressure: .normal, pressurePercent: 38, swapUsed: 1.2e9, swapTotal: 2e9, pageIns: 1.9e6,
                                  pageOuts: 42e3, swapIns: 18204, swapOuts: 9771, compressions: 2.4e6, decompressions: 1.8e6)
        s.network = NetworkSnapshot(interfaces: [
            InterfaceStat(bsdName: "en0", displayName: "Wi-Fi", ipv4: "192.168.1.24", downBps: 1.2e6, upBps: 320e3,
                          linkBitsPerSecond: 1.2e9, totalIn: 41e9, totalOut: 7.9e9)])
        s.diskUsage = DiskUsageSnapshot(volumes: [VolumeStat(path: "/", name: "Macintosh HD", total: 994e9, available: 412e9,
                                                             purgeable: 23e9, isRoot: true, isInternal: true)])
        s.processes = ProcessesSnapshot(processes: [ProcessStat(pid: 1, name: "Xcode", cpu: 48.2, memory: 1.9e9, readBps: 0, writeBps: 1.4e6)],
                                        otherCPU: 12)
        return s
    }

    func item(_ id: String) -> ItemConfig { AppConfig.default.item(id: id)! }

    func testMenuBarTextsMatchWireframe() {
        let s = sampleState()
        let cpu = ItemPresenter(item: item("cpu"), state: s, units: .base1000)
        XCTAssertEqual(cpu.menuBarText, "23%")
        XCTAssertEqual(cpu.bigValue, "23%")
        XCTAssertEqual(cpu.subLine, "2 cores · 1 performance, 1 efficiency")
        let mem = ItemPresenter(item: item("mem"), state: s, units: .base1000)
        XCTAssertEqual(mem.menuBarText, "53%")
        XCTAssertEqual(mem.bigValue, "16.9 GB")
        XCTAssertEqual(mem.rows.first { $0.id == "pressure" }?.pillLevel, .ok)
        let net = ItemPresenter(item: item("net"), state: s, units: .base1000)
        XCTAssertEqual(net.menuBarTwo.0, "↑ 320 KB/s")
        XCTAssertEqual(net.menuBarTwo.1, "↓ 1.2 MB/s")
        XCTAssertEqual(net.summaryText, "↑ 320 KB/s · ↓ 1.2 MB/s")
        let du = ItemPresenter(item: item("du"), state: s, units: .base1000)
        XCTAssertEqual(du.bigValue, "412 GB free")
        XCTAssertEqual(du.menuBarText, "412 GB")
        XCTAssertEqual(du.chartMax, 1000e9)
        let gpu = ItemPresenter(item: item("gpu"), state: s, units: .base1000)
        XCTAssertFalse(gpu.available)
        XCTAssertEqual(gpu.bigValue, "–")
    }

    func testRowsFollowSpec() {
        let s = sampleState()
        let rows = ItemPresenter(item: item("cpu"), state: s, units: .base1000).rows
        XCTAssertEqual(rows.map(\.label), ["User", "System", "Idle", "Per core", "Top processes", "Load average", "Temperature and clock"])
        XCTAssertEqual(rows.compactMap(\.breakdown), [.perCore, .cpuProcesses, .loadAverage, .cpuSensors])
        XCTAssertEqual(rows[3].value, "busiest P1 · 61%")
        let du = ItemPresenter(item: item("du"), state: s, units: .base1000).rows
        XCTAssertEqual(du.map(\.label), ["Used", "Available", "Purgeable (counted as free)", "Volumes", "Largest folders", "Trend"])
    }

    func testHistoryValues() {
        let s = sampleState()
        let v = ItemPresenter(item: item("cpu"), state: s, units: .base1000).historyValues
        XCTAssertEqual(v["usr"], 14)
        XCTAssertEqual(v["main"], 23)
        XCTAssertEqual(ItemPresenter(item: item("net"), state: s, units: .base1000).historyValues["down"], 1.2e6)
    }

    func testBreakdowns() {
        let s = sampleState()
        var cpuItem = item("cpu")
        cpuItem.breakdownRows = 5
        let b = BreakdownPresenter(item: cpuItem, state: s, units: .base1000, history: HistoryStore(), now: 0)
        guard case .list(let rows) = b.model(.cpuProcesses).content else { return XCTFail("expected list") }
        XCTAssertEqual(rows.map(\.name), ["Xcode", "System and other users"])
        guard case .bars(let groups) = b.model(.perCore).content else { return XCTFail("expected bars") }
        XCTAssertEqual(groups.map(\.name), ["Performance cores", "Efficiency cores"])
        XCTAssertEqual(b.model(.loadAverage).chartKey, "cpu.load")
        XCTAssertNotNil(b.model(.cpuSensors).note)
        let net = BreakdownPresenter(item: item("net"), state: s, units: .base1000, history: HistoryStore(), now: 0)
        XCTAssertEqual(net.model(.netApps).emptyText, "Collecting…")
        let du = BreakdownPresenter(item: item("du"), state: s, units: .base1000, history: HistoryStore(), now: 0)
        XCTAssertEqual(du.model(.largestFolders).action, .scanFolders)
    }
}

/// Regression tests for the independent review findings.
final class ReviewFixTests: XCTestCase {
    func testBadItemValuesFallBackToDefaults() throws {
        let json = #"{"items":[{"id":"cpu","kind":"cpu","menuBarChartSeconds":-5,"sampleSeconds":0,"breakdownRows":-1}]}"#
        let c = try ConfigStore.decode(Data(json.utf8))
        XCTAssertEqual(c.items[0].menuBarChartSeconds, 60)
        XCTAssertEqual(c.items[0].sampleSeconds, 1)
        XCTAssertEqual(c.items[0].breakdownRows, 8)
        XCTAssertEqual(HistoryStore().recent("x", count: -3), [])
        XCTAssertEqual(RingBuffer<Int>(capacity: 2).suffix(-1), [])
    }

    func testOneBadItemDoesNotDropTheList() throws {
        let json = #"{"items":[{"id":"cpu","kind":"cpu"},{"id":"bad","kind":"cpu","showInMenuBar":"yes"},{"id":"mem","kind":"memory"}]}"#
        let c = try ConfigStore.decode(Data(json.utf8))
        XCTAssertEqual(c.items.map(\.id), ["cpu", "mem"])
    }

    func testSlowSeriesAreSaved() {
        // CPU every second, disk usage every 10 minutes, for 3 hours.
        var h = HistoryStore()
        var marks: [String: [Int: Double]] = [:]
        var saved: [String: Int] = [:]
        for t in stride(from: 0.0, through: 3 * 3600, by: 1) {
            var v = ["cpu.main": 10.0]
            if Int(t) % 600 == 0 { v["du.used"] = 500 }
            h.record(v, at: t)
            if Int(t) % 30 == 0 {
                for row in h.unsaved(after: marks) {
                    saved[row.key, default: 0] += 1
                    marks[row.key, default: [:]][row.tier] = max(marks[row.key]?[row.tier] ?? -.infinity, row.bucket.t)
                }
            }
        }
        XCTAssertGreaterThan(saved["cpu.main"] ?? 0, 1000)
        XCTAssertGreaterThan(saved["du.used"] ?? 0, 30)
        // Nothing is saved twice.
        XCTAssertTrue(h.unsaved(after: marks).isEmpty)
    }

    func testRecentBySeconds() {
        var s = TieredSeries()
        for t in stride(from: 0.0, through: 120, by: 2) { s.append(t, at: t) }
        let last = s.recent(seconds: 60, now: 120)
        XCTAssertEqual(last.count, 30)
        XCTAssertEqual(last.last, 120)
    }

    func testResizeKeepsOpenBucketWithoutDuplicates() {
        var h = HistoryStore(keepDays: 30)
        for t in 0..<25 { h.record(["k": Double(t)], at: Double(t)) }
        let before = h.series["k"]!.buckets(tier: 1).map(\.t)
        h.setKeepDays(7)
        h.record(["k": 99], at: 25)
        let after = h.series["k"]!.buckets(tier: 1).map(\.t)
        XCTAssertEqual(before, [0, 10, 20])
        XCTAssertEqual(after, [0, 10, 20])
        XCTAssertEqual(Set(after).count, after.count)
    }
}
