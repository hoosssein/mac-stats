#if os(macOS)
import Foundation
import IOKit.ps
import StatsCore

/// Data layer: runs the collectors. One call per second from the store; each kind is sampled when its
/// interval has passed. See docs/kb/architecture.md "Sampling schedule".
public actor Sampler {
    public struct Request: Sendable {
        /// Seconds between samples for each kind. Kinds not listed are not sampled.
        public var intervals: [MetricKind: Double]
        /// Scan processes this often (nil = do not scan).
        public var processInterval: Double?
        /// Sample per-app GPU time (only while GPU → Top apps is open).
        public var gpuApps: Bool
        /// Sample disk usage now, even if 10 minutes have not passed.
        public var forceDiskUsage: Bool

        public init(intervals: [MetricKind: Double], processInterval: Double?, gpuApps: Bool, forceDiskUsage: Bool) {
            self.intervals = intervals; self.processInterval = processInterval
            self.gpuApps = gpuApps; self.forceDiskUsage = forceDiskUsage
        }
    }

    private let cpu = CPUCollector()
    private let memory = MemoryCollector()
    private let network = NetworkCollector()
    private let gpu = GPUCollector()
    private let diskIO = DiskIOCollector()
    private let diskUsage = DiskUsageCollector()
    private let processes = ProcessCollector()
    private var last: [MetricKind: Double] = [:]
    private var lastProcesses: Double = 0
    private var lastGPUApps: Double = 0
    private var latestCPUTotal: Double?

    public init() {}

    public func sample(_ request: Request) -> SampleResult {
        let now = monotonicSeconds()
        var result = SampleResult(time: Date().timeIntervalSince1970)
        func due(_ kind: MetricKind) -> Bool {
            guard let interval = request.intervals[kind] else { return false }
            // Allow a little jitter so a 1 s interval is not skipped when the timer fires early.
            return now - (last[kind] ?? -1e9) >= interval - 0.2
        }
        if due(.cpu) {
            last[.cpu] = now
            result.cpu = cpu.sample()
            if let c = result.cpu { latestCPUTotal = c.total }
        }
        if due(.memory) { last[.memory] = now; result.memory = memory.sample() }
        if due(.network) { last[.network] = now; result.network = network.sample() }
        if due(.gpu) { last[.gpu] = now; result.gpu = gpu.sample() }
        if due(.diskIO) { last[.diskIO] = now; result.diskIO = diskIO.sample() }
        if request.intervals[.diskUsage] != nil && (request.forceDiskUsage || due(.diskUsage)) {
            last[.diskUsage] = now
            result.diskUsage = diskUsage.sample()
        }
        if let every = request.processInterval, now - lastProcesses >= every - 0.2 {
            lastProcesses = now
            result.processes = processes.sample(totalCPU: latestCPUTotal, cores: max(1, cpu.coreCount))
        }
        if request.gpuApps, now - lastGPUApps >= 1.8 {
            lastGPUApps = now
            result.gpuApps = gpu.sampleApps()
        }
        return result
    }
}

/// Data layer: `nettop` takes about a second, so it runs on its own actor, apart from the 1 s loop.
public actor NetTopSampler {
    private let collector = NetTopCollector()

    public init() {}

    /// Nil when `nettop` is not available.
    public func sample() -> [NetAppStat]? { collector.sample() }
}

/// Data layer: power source and screen lock.
public enum SystemState {
    /// True when the Mac runs on battery power.
    public static var onBattery: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? else { return false }
        return type == "Battery Power"
    }
}

/// Data layer: creates the on-request folder scan.
public final class FolderScan: @unchecked Sendable {
    private let scanner = FolderScanner()

    public init() {}

    public func run(progress: @escaping @Sendable ([FolderSize]) -> Void) async -> [FolderSize] {
        await Task.detached(priority: .utility) { [scanner] in
            scanner.scan(progress: progress)
        }.value
    }

    public func cancel() { scanner.cancel() }
}
#endif
