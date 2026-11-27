#if os(macOS)
import Foundation
import IOKit
import StatsCore

/// Data layer: shared IOKit helpers.
enum IORegistry {
    /// Calls `body` for each service matching `className`. Services are released afterwards.
    static func forEach(matching className: String, _ body: (io_registry_entry_t) -> Void) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            body(service)
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
    }

    static func properties(_ entry: io_registry_entry_t) -> [String: Any]? {
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return nil }
        return dict
    }

    static func children(_ entry: io_registry_entry_t, _ body: (io_registry_entry_t) -> Void) {
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(entry, "IOService", &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        var child = IOIteratorNext(iterator)
        while child != 0 {
            body(child)
            IOObjectRelease(child)
            child = IOIteratorNext(iterator)
        }
    }

    static func parent(_ entry: io_registry_entry_t) -> io_registry_entry_t? {
        var parent: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(entry, "IOService", &parent) == KERN_SUCCESS, parent != 0 else { return nil }
        return parent
    }

    static func className(_ entry: io_registry_entry_t) -> String {
        var buf = [CChar](repeating: 0, count: 128)
        IOObjectGetClass(entry, &buf)
        return String(cString: buf)
    }

    static func entryID(_ entry: io_registry_entry_t) -> UInt64 {
        var id: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(entry, &id)
        return id
    }

    static func number(_ any: Any?) -> Double? { (any as? NSNumber)?.doubleValue }

    static func string(_ any: Any?) -> String? {
        if let s = any as? String { return s }
        if let d = any as? Data { return String(decoding: d.prefix { $0 != 0 }, as: UTF8.self) }
        return nil
    }
}

/// Data layer: GPU utilization from `IOAccelerator` → `PerformanceStatistics`.
/// Per-app GPU time (experimental, Apple silicon) from `AGXDeviceUserClient` children.
final class GPUCollector {
    private var previousAppTime: [Int32: (name: String, ns: Double)] = [:]
    private var previousAppSample: Double = 0

    func sample() -> GPUSnapshot? {
        var best: GPUSnapshot?
        IORegistry.forEach(matching: "IOAccelerator") { service in
            guard let props = IORegistry.properties(service),
                  let perf = props["PerformanceStatistics"] as? [String: Any] else { return }
            let device = IORegistry.number(perf["Device Utilization %"]) ?? IORegistry.number(perf["GPU Activity(%)"]) ?? 0
            let renderer = IORegistry.number(perf["Renderer Utilization %"]) ?? device
            let tiler = IORegistry.number(perf["Tiler Utilization %"]) ?? 0
            let inUse = IORegistry.number(perf["In use system memory"]) ?? IORegistry.number(perf["vramUsedBytes"])
            let alloc = IORegistry.number(perf["Alloc system memory"]) ?? IORegistry.number(perf["vramFreeBytes"]).flatMap { free in inUse.map { $0 + free } }
            var name = IORegistry.string(props["model"]) ?? "GPU"
            if let cores = IORegistry.number(props["gpu-core-count"]) { name += " · \(Int(cores))-core GPU" }
            let snap = GPUSnapshot(name: name, device: min(100, device), renderer: min(100, renderer), tiler: min(100, tiler),
                                   memoryInUse: inUse, memoryAllocated: alloc)
            if best == nil || snap.device > best!.device { best = snap }
        }
        return best
    }

    /// Share of GPU time per process since the last call.
    /// Nil on the first call (needs two readings). Empty when the keys are missing (not available on this Mac).
    func sampleApps() -> [GPUAppStat]? {
        let now = monotonicSeconds()
        var current: [Int32: (name: String, ns: Double)] = [:]
        IORegistry.forEach(matching: "IOAccelerator") { service in
            IORegistry.children(service) { child in
                guard IORegistry.className(child).contains("UserClient"),
                      let props = IORegistry.properties(child),
                      let creator = props["IOUserClientCreator"] as? String,
                      let usage = props["AppUsage"] as? [[String: Any]] else { return }
                // Creator looks like "pid 123, WindowServer".
                let parts = creator.components(separatedBy: ", ")
                guard let pidText = parts.first?.replacingOccurrences(of: "pid ", with: ""), let pid = Int32(pidText) else { return }
                let name = parts.dropFirst().joined(separator: ", ")
                let ns = usage.compactMap { IORegistry.number($0["accumulatedGPUTime"]) }.reduce(0, +)
                let prev = current[pid]?.ns ?? 0
                current[pid] = (name, prev + ns)
            }
        }
        defer { previousAppTime = current; previousAppSample = now }
        let dt = now - previousAppSample
        if current.isEmpty { return [] }
        guard previousAppSample > 0, dt > 0, dt < 60 else { return nil }
        var result: [String: GPUAppStat] = [:]
        for (pid, cur) in current {
            guard let prev = previousAppTime[pid], cur.ns >= prev.ns else { continue }
            let share = min(100, (cur.ns - prev.ns) / (dt * 1e9) * 100)
            if var existing = result[cur.name] {
                existing.share += share
                result[cur.name] = existing
            } else {
                result[cur.name] = GPUAppStat(name: cur.name, pid: pid, share: share)
            }
        }
        return Array(result.values)
    }
}

/// Data layer: disk throughput from `IOBlockStorageDriver` → `Statistics`.
final class DiskIOCollector {
    private struct Reading { var readBytes, writeBytes, readOps, writeOps, readTime, writeTime: Double }
    private var previous: [UInt64: Reading] = [:]
    private var previousTime: Double = 0

    func sample() -> DiskIOSnapshot? {
        let now = monotonicSeconds()
        var current: [UInt64: (Reading, String, String)] = [:]
        IORegistry.forEach(matching: "IOBlockStorageDriver") { driver in
            guard let props = IORegistry.properties(driver),
                  let stats = props["Statistics"] as? [String: Any] else { return }
            var name = "Disk", detail = ""
            if let parent = IORegistry.parent(driver) {
                if let p = IORegistry.properties(parent) {
                    let chars = p["Device Characteristics"] as? [String: Any]
                    let proto = p["Protocol Characteristics"] as? [String: Any]
                    name = (IORegistry.string(chars?["Product Name"]) ?? name).trimmingCharacters(in: .whitespaces)
                    let location = IORegistry.string(proto?["Physical Interconnect Location"]) ?? ""
                    let interconnect = IORegistry.string(proto?["Physical Interconnect"]) ?? ""
                    detail = [location, interconnect].filter { !$0.isEmpty }.joined(separator: " · ")
                }
                IOObjectRelease(parent)
            }
            if name.localizedCaseInsensitiveContains("disk image") { return }
            let r = Reading(readBytes: IORegistry.number(stats["Bytes (Read)"]) ?? 0,
                            writeBytes: IORegistry.number(stats["Bytes (Write)"]) ?? 0,
                            readOps: IORegistry.number(stats["Operations (Read)"]) ?? 0,
                            writeOps: IORegistry.number(stats["Operations (Write)"]) ?? 0,
                            readTime: IORegistry.number(stats["Total Time (Read)"]) ?? 0,
                            writeTime: IORegistry.number(stats["Total Time (Write)"]) ?? 0)
            current[IORegistry.entryID(driver)] = (r, name, detail.isEmpty ? "Disk" : detail)
        }
        defer { previous = current.mapValues(\.0); previousTime = now }
        let dt = now - previousTime
        guard previousTime > 0, dt > 0 else { return nil }

        var disks: [DiskStat] = []
        var rOps = 0.0, wOps = 0.0, rTime = 0.0, wTime = 0.0
        for (id, entry) in current {
            guard let p = previous[id] else { continue }
            let c = entry.0
            func d(_ a: Double, _ b: Double) -> Double { max(0, a - b) }
            disks.append(DiskStat(name: entry.1, detail: entry.2,
                                  readBps: d(c.readBytes, p.readBytes) / dt, writeBps: d(c.writeBytes, p.writeBytes) / dt))
            rOps += d(c.readOps, p.readOps); wOps += d(c.writeOps, p.writeOps)
            rTime += d(c.readTime, p.readTime); wTime += d(c.writeTime, p.writeTime)
        }
        disks.sort { $0.name < $1.name }
        return DiskIOSnapshot(disks: disks, readOps: rOps / dt, writeOps: wOps / dt,
                              readLatencyMs: rOps > 0 ? rTime / rOps / 1e6 : 0,
                              writeLatencyMs: wOps > 0 ? wTime / wOps / 1e6 : 0)
    }
}

/// Data layer: mounted volumes and their free space.
final class DiskUsageCollector {
    private let keys: [URLResourceKey] = [
        .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
        .volumeAvailableCapacityForImportantUsageKey, .volumeIsRootFileSystemKey,
        .volumeIsInternalKey, .volumeIsBrowsableKey, .volumeIsLocalKey,
    ]

    func sample() -> DiskUsageSnapshot? {
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                                  options: [.skipHiddenVolumes]) else { return nil }
        var volumes: [VolumeStat] = []
        for url in urls {
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            let path = url.path
            if path.hasPrefix("/System/Volumes") { continue }
            if v.volumeIsBrowsable == false || v.volumeIsLocal == false { continue }
            guard let total = v.volumeTotalCapacity, total > 0 else { continue }
            let plain = Double(v.volumeAvailableCapacity ?? 0)
            let important = v.volumeAvailableCapacityForImportantUsage.map(Double.init) ?? plain
            let isRoot = v.volumeIsRootFileSystem ?? (path == "/")
            volumes.append(VolumeStat(path: isRoot ? "/" : path, name: v.volumeName ?? url.lastPathComponent,
                                      total: Double(total), available: max(important, plain),
                                      purgeable: max(0, important - plain), isRoot: isRoot,
                                      isInternal: v.volumeIsInternal ?? isRoot))
        }
        volumes.sort { ($0.isRoot ? 0 : 1, $0.name) < ($1.isRoot ? 0 : 1, $1.name) }
        return DiskUsageSnapshot(volumes: volumes)
    }
}
#endif
