#if os(macOS)
import Darwin
import Foundation
import StatsCore

/// Data layer: per-process CPU, memory and disk from `proc_pid_rusage`.
/// Processes owned by other users refuse the call; their CPU is reported as one remainder.
final class ProcessCollector {
    private struct Reading { var cpuNanos: Double; var readBytes: Double; var writeBytes: Double }

    private var previous: [Int32: Reading] = [:]
    private var previousTime: Double = 0
    private var names: [Int32: String] = [:]

    /// `totalCPU` is the machine's busy percent (0–100) and `cores` the core count,
    /// used to compute "System and other users". Returns nil on the first call.
    func sample(totalCPU: Double?, cores: Int) -> ProcessesSnapshot? {
        let now = monotonicSeconds()
        let pids = listPIDs()
        var current: [Int32: Reading] = [:]
        var footprints: [Int32: Double] = [:]
        for pid in pids where pid > 0 {
            var info = rusage_info_v4()
            let rc = withUnsafeMutablePointer(to: &info) { ptr in
                ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            guard rc == 0 else { continue }
            let cpu = Double(info.ri_user_time &+ info.ri_system_time) * MachTime.nanosPerTick
            current[pid] = Reading(cpuNanos: cpu, readBytes: Double(info.ri_diskio_bytesread),
                                   writeBytes: Double(info.ri_diskio_byteswritten))
            footprints[pid] = Double(info.ri_phys_footprint)
            if names[pid] == nil { names[pid] = processName(pid) }
        }

        let dt = now - previousTime
        let firstRound = previousTime == 0 || dt > 30
        defer {
            previous = current
            previousTime = now
            names = names.filter { current[$0.key] != nil }
        }
        guard !firstRound, dt > 0 else { return nil }

        var stats: [ProcessStat] = []
        var measured = 0.0
        for (pid, c) in current {
            let p = previous[pid]
            let cpu = p.map { max(0, c.cpuNanos - $0.cpuNanos) / (dt * 1e9) * 100 } ?? 0
            let rd = p.map { max(0, c.readBytes - $0.readBytes) / dt } ?? 0
            let wr = p.map { max(0, c.writeBytes - $0.writeBytes) / dt } ?? 0
            measured += cpu
            stats.append(ProcessStat(pid: pid, name: names[pid] ?? "pid \(pid)", cpu: cpu,
                                     memory: footprints[pid] ?? 0, readBps: rd, writeBps: wr))
        }
        let other = totalCPU.map { max(0, $0 * Double(max(1, cores)) - measured) } ?? 0
        return ProcessesSnapshot(processes: stats, otherCPU: other)
    }

    private func listPIDs() -> [Int32] {
        let estimate = Int(proc_listallpids(nil, 0))
        guard estimate > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: estimate + 64)
        let n = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size)))
        return Array(pids.prefix(max(0, n)))
    }

    private func processName(_ pid: Int32) -> String {
        // The executable name inside an app bundle is the friendliest name we can get without AppKit.
        var pathBuf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        if proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count)) > 0 {
            let path = String(cString: pathBuf)
            if let range = path.range(of: ".app/Contents/MacOS/") {
                let exe = String(path[range.upperBound...])
                if !exe.contains("/") { return exe }
            }
            let last = (path as NSString).lastPathComponent
            if !last.isEmpty { return last }
        }
        var nameBuf = [CChar](repeating: 0, count: 256)
        if proc_name(pid, &nameBuf, UInt32(nameBuf.count)) > 0 { return String(cString: nameBuf) }
        return "pid \(pid)"
    }
}

/// Data layer: per-app network traffic from `nettop` (experimental, tool output).
/// Runs only while the Network → Top apps panel is open. Blocks about one second.
final class NetTopCollector {
    /// Nil when `nettop` could not run or printed nothing we understand (not available on this Mac).
    func sample() -> [NetAppStat]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = ["-P", "-L", "2", "-s", "1", "-d", "-x", "-n", "-J", "bytes_in,bytes_out"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let deadline = DispatchTime.now() + .seconds(5)
        DispatchQueue.global().asyncAfter(deadline: deadline) { [weak process] in
            if let p = process, p.isRunning { p.terminate() }
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0, text.contains("bytes_in") else { return nil }
        return NetTopCollector.parse(text)
    }

    /// Parses `nettop -L` CSV. Each sample block starts with a header line that contains "bytes_in".
    /// Rows contain a "name.pid" field followed by bytes in and bytes out. The last block holds the deltas.
    static func parse(_ text: String) -> [NetAppStat] {
        var block: [String: (Double, Double)] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            if line.contains("bytes_in") { block = [:]; continue }
            let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard let idx = fields.firstIndex(where: { f in
                guard let dot = f.lastIndex(of: ".") else { return false }
                return Int(f[f.index(after: dot)...]) != nil && dot != f.startIndex
            }) else { continue }
            let numbers = fields[(idx + 1)...].compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard numbers.count >= 2 else { continue }
            let raw = fields[idx]
            let name = String(raw[..<raw.lastIndex(of: ".")!])
            let prev = block[name] ?? (0, 0)
            block[name] = (prev.0 + numbers[0], prev.1 + numbers[1])
        }
        // -s 1 makes the delta block cover one second, so bytes equal bytes per second.
        return block.map { NetAppStat(name: $0.key, downBps: $0.value.0, upBps: $0.value.1) }
            .filter { $0.downBps + $0.upBps > 0 }
    }
}

/// Data layer: on-request scan of the largest folders (home top-level folders and /Applications).
final class FolderScanner: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() { lock.lock(); cancelled = true; lock.unlock() }

    private var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }

    /// Scans folders one by one and reports results after each folder. Unreadable files are skipped.
    func scan(progress: @escaping @Sendable ([FolderSize]) -> Void) -> [FolderSize] {
        lock.lock(); cancelled = false; lock.unlock()
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var targets: [URL] = (try? fm.contentsOfDirectory(at: home, includingPropertiesForKeys: [.isDirectoryKey],
                                                            options: [.skipsHiddenFiles])) ?? []
        targets = targets.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        targets.append(URL(fileURLWithPath: "/Applications"))

        var results: [FolderSize] = []
        for url in targets {
            if isCancelled { break }
            let bytes = size(of: url)
            let name = url.path == "/Applications" ? "/Applications" : "~/" + url.lastPathComponent
            results.append(FolderSize(name: name, path: url.path, bytes: bytes))
            progress(results)
        }
        return results
    }

    private func size(of url: URL) -> Double {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [],
                                                      errorHandler: { _, _ in true }) else { return 0 }
        var total = 0.0
        var n = 0
        for case let file as URL in e {
            n += 1
            if n % 2000 == 0 && isCancelled { break }
            guard let v = try? file.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            total += Double(v.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
#endif
