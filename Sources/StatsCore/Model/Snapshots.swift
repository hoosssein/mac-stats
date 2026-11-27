import Foundation

// Model layer: plain values produced by the collectors (StatsKit) and read by the UI.

public struct CoreLoad: Sendable, Equatable {
    public var name: String
    public var isPerformance: Bool
    /// Busy percent, 0–100.
    public var usage: Double

    public init(name: String, isPerformance: Bool, usage: Double) {
        self.name = name; self.isPerformance = isPerformance; self.usage = usage
    }
}

public struct CPUSnapshot: Sendable, Equatable {
    /// Percent of all cores, 0–100.
    public var user: Double
    public var system: Double
    public var idle: Double
    public var cores: [CoreLoad]
    public var performanceCores: Int
    public var efficiencyCores: Int
    public var load1: Double
    public var load5: Double
    public var load15: Double
    public var processCount: Int
    public var threadCount: Int
    public var uptime: Double

    public var total: Double { user + system }
    public var busiestCore: CoreLoad? { cores.max { $0.usage < $1.usage } }

    public init(user: Double, system: Double, idle: Double, cores: [CoreLoad], performanceCores: Int,
                efficiencyCores: Int, load1: Double, load5: Double, load15: Double,
                processCount: Int, threadCount: Int, uptime: Double) {
        self.user = user; self.system = system; self.idle = idle; self.cores = cores
        self.performanceCores = performanceCores; self.efficiencyCores = efficiencyCores
        self.load1 = load1; self.load5 = load5; self.load15 = load15
        self.processCount = processCount; self.threadCount = threadCount; self.uptime = uptime
    }
}

public enum PressureLevel: Int, Sendable, Equatable {
    case normal = 1, warning = 2, critical = 4

    public var title: String {
        switch self {
        case .normal: return "Normal"
        case .warning: return "Warning"
        case .critical: return "Critical"
        }
    }
}

public struct MemorySnapshot: Sendable, Equatable {
    public var total: Double
    public var app: Double
    public var wired: Double
    public var compressed: Double
    public var cached: Double
    public var free: Double
    public var pressure: PressureLevel
    /// 100 − `kern.memorystatus_level` (free percentage). Nil when not available.
    public var pressurePercent: Double?
    public var swapUsed: Double
    public var swapTotal: Double
    public var pageIns: Double
    public var pageOuts: Double
    public var swapIns: Double
    public var swapOuts: Double
    public var compressions: Double
    public var decompressions: Double

    /// Used memory as Activity Monitor shows it: app + wired + compressed.
    public var used: Double { app + wired + compressed }

    public init(total: Double, app: Double, wired: Double, compressed: Double, cached: Double, free: Double,
                pressure: PressureLevel, pressurePercent: Double?, swapUsed: Double, swapTotal: Double,
                pageIns: Double, pageOuts: Double,
                swapIns: Double, swapOuts: Double, compressions: Double, decompressions: Double) {
        self.total = total; self.app = app; self.wired = wired; self.compressed = compressed; self.cached = cached
        self.free = free; self.pressure = pressure; self.pressurePercent = pressurePercent
        self.swapUsed = swapUsed; self.swapTotal = swapTotal
        self.pageIns = pageIns; self.pageOuts = pageOuts; self.swapIns = swapIns; self.swapOuts = swapOuts
        self.compressions = compressions; self.decompressions = decompressions
    }
}

public struct InterfaceStat: Sendable, Equatable {
    public var bsdName: String
    public var displayName: String
    public var ipv4: String?
    public var downBps: Double
    public var upBps: Double
    public var linkBitsPerSecond: Double
    public var totalIn: Double
    public var totalOut: Double

    public init(bsdName: String, displayName: String, ipv4: String?, downBps: Double, upBps: Double,
                linkBitsPerSecond: Double, totalIn: Double, totalOut: Double) {
        self.bsdName = bsdName; self.displayName = displayName; self.ipv4 = ipv4
        self.downBps = downBps; self.upBps = upBps; self.linkBitsPerSecond = linkBitsPerSecond
        self.totalIn = totalIn; self.totalOut = totalOut
    }
}

public struct NetworkSnapshot: Sendable, Equatable {
    public var interfaces: [InterfaceStat]
    /// Bytes received and sent since midnight (all interfaces), counted while the app runs.
    public var todayIn: Double
    public var todayOut: Double
    /// Highest download rate seen today and when.
    public var peakToday: Double
    public var peakTodayAt: Double

    public init(interfaces: [InterfaceStat], todayIn: Double = 0, todayOut: Double = 0,
                peakToday: Double = 0, peakTodayAt: Double = 0) {
        self.interfaces = interfaces; self.todayIn = todayIn; self.todayOut = todayOut
        self.peakToday = peakToday; self.peakTodayAt = peakTodayAt
    }

    /// Rates for one interface, or the sum of all when `target` is nil.
    public func rates(target: String?) -> (down: Double, up: Double) {
        let list = target.map { t in interfaces.filter { $0.bsdName == t } } ?? interfaces
        return (list.reduce(0) { $0 + $1.downBps }, list.reduce(0) { $0 + $1.upBps })
    }

    public var totalsSinceBoot: (down: Double, up: Double) {
        (interfaces.reduce(0) { $0 + $1.totalIn }, interfaces.reduce(0) { $0 + $1.totalOut })
    }

    /// Interfaces that moved data or have an address (the "active" ones).
    public var activeInterfaces: [InterfaceStat] {
        interfaces.filter { $0.ipv4 != nil || $0.downBps > 0 || $0.upBps > 0 }
    }
}

public struct GPUSnapshot: Sendable, Equatable {
    public var name: String
    public var device: Double
    public var renderer: Double
    public var tiler: Double
    public var memoryInUse: Double?
    public var memoryAllocated: Double?

    public init(name: String, device: Double, renderer: Double, tiler: Double,
                memoryInUse: Double?, memoryAllocated: Double?) {
        self.name = name; self.device = device; self.renderer = renderer; self.tiler = tiler
        self.memoryInUse = memoryInUse; self.memoryAllocated = memoryAllocated
    }
}

public struct DiskStat: Sendable, Equatable {
    public var name: String
    public var detail: String
    public var readBps: Double
    public var writeBps: Double

    public init(name: String, detail: String, readBps: Double, writeBps: Double) {
        self.name = name; self.detail = detail; self.readBps = readBps; self.writeBps = writeBps
    }
}

public struct DiskIOSnapshot: Sendable, Equatable {
    public var disks: [DiskStat]
    public var readOps: Double
    public var writeOps: Double
    public var readLatencyMs: Double
    public var writeLatencyMs: Double

    public var readBps: Double { disks.reduce(0) { $0 + $1.readBps } }
    public var writeBps: Double { disks.reduce(0) { $0 + $1.writeBps } }

    public init(disks: [DiskStat], readOps: Double, writeOps: Double, readLatencyMs: Double, writeLatencyMs: Double) {
        self.disks = disks; self.readOps = readOps; self.writeOps = writeOps
        self.readLatencyMs = readLatencyMs; self.writeLatencyMs = writeLatencyMs
    }
}

public struct VolumeStat: Sendable, Equatable {
    public var path: String
    public var name: String
    public var total: Double
    /// Available for important usage: counts purgeable space as free, like Finder.
    public var available: Double
    /// Purgeable space (counted as free above).
    public var purgeable: Double
    public var isRoot: Bool
    public var isInternal: Bool

    public var used: Double { max(0, total - available) }

    public init(path: String, name: String, total: Double, available: Double, purgeable: Double,
                isRoot: Bool, isInternal: Bool) {
        self.path = path; self.name = name; self.total = total; self.available = available
        self.purgeable = purgeable; self.isRoot = isRoot; self.isInternal = isInternal
    }
}

public struct DiskUsageSnapshot: Sendable, Equatable {
    public var volumes: [VolumeStat]

    public init(volumes: [VolumeStat]) { self.volumes = volumes }

    /// The volume for an item target. Nil target or "/" means the boot volume.
    public func volume(for target: String?) -> VolumeStat? {
        if let target, target != "/" { return volumes.first { $0.path == target } }
        return volumes.first(where: \.isRoot) ?? volumes.first
    }
}

public struct ProcessStat: Sendable, Equatable {
    public var pid: Int32
    public var name: String
    /// Percent of one core (can exceed 100).
    public var cpu: Double
    /// Physical footprint in bytes.
    public var memory: Double
    public var readBps: Double
    public var writeBps: Double

    public init(pid: Int32, name: String, cpu: Double, memory: Double, readBps: Double, writeBps: Double) {
        self.pid = pid; self.name = name; self.cpu = cpu; self.memory = memory
        self.readBps = readBps; self.writeBps = writeBps
    }
}

public struct ProcessesSnapshot: Sendable, Equatable {
    public var processes: [ProcessStat]
    /// CPU used by processes we cannot measure (other users, root), in % of one core.
    public var otherCPU: Double

    public init(processes: [ProcessStat], otherCPU: Double) {
        self.processes = processes; self.otherCPU = otherCPU
    }
}

public struct NetAppStat: Sendable, Equatable {
    public var name: String
    public var downBps: Double
    public var upBps: Double

    public init(name: String, downBps: Double, upBps: Double) {
        self.name = name; self.downBps = downBps; self.upBps = upBps
    }
}

public struct GPUAppStat: Sendable, Equatable {
    public var name: String
    public var pid: Int32
    /// Share of GPU time in the last interval, 0–100.
    public var share: Double

    public init(name: String, pid: Int32, share: Double) {
        self.name = name; self.pid = pid; self.share = share
    }
}

public struct FolderSize: Sendable, Equatable {
    public var name: String
    public var path: String
    public var bytes: Double

    public init(name: String, path: String, bytes: Double) {
        self.name = name; self.path = path; self.bytes = bytes
    }
}

/// State of the on-request "Largest folders" scan.
public struct FolderScanState: Sendable, Equatable {
    public var results: [FolderSize] = []
    public var isRunning = false
    public var finishedAt: Double?
    public var duration: Double?

    public init() {}
}

/// Everything the collectors know right now.
public struct LiveState: Sendable, Equatable {
    public var time: Double = 0
    public var cpu: CPUSnapshot?
    public var memory: MemorySnapshot?
    public var network: NetworkSnapshot?
    public var gpu: GPUSnapshot?
    public var diskIO: DiskIOSnapshot?
    public var diskUsage: DiskUsageSnapshot?
    public var processes: ProcessesSnapshot?
    /// Nil = not sampled yet (panel not open). Empty = sampled, nothing found or not available.
    public var netApps: [NetAppStat]?
    public var gpuApps: [GPUAppStat]?

    public init() {}
}
