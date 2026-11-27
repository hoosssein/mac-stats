#if os(macOS)
import Darwin
import Foundation
import StatsCore

/// Data layer: CPU totals and per-core load from `host_processor_info`. See docs/kb/data-sources.md.
final class CPUCollector {
    private let host = mach_host_self()
    private var previous: [CPUTicks] = []
    private let performanceCores = Sysctl.int("hw.perflevel0.logicalcpu") ?? 0
    private let efficiencyCores = Sysctl.int("hw.perflevel1.logicalcpu") ?? 0

    /// Returns nil on the first call (it needs two readings) or on error.
    func sample(threadCount: Int) -> CPUSnapshot? {
        guard let ticks = readTicks() else { return nil }
        defer { previous = ticks }
        guard previous.count == ticks.count, !ticks.isEmpty else { return nil }

        let total = CPUUsage.average(Array(zip(previous, ticks)))
        let hasLevels = performanceCores > 0 && efficiencyCores > 0 && performanceCores + efficiencyCores == ticks.count
        var cores: [CoreLoad] = []
        for (i, pair) in zip(previous, ticks).enumerated() {
            let usage = CPUUsage.between(pair.0, pair.1).total
            if hasLevels {
                // On Apple silicon the efficiency cores come first.
                let isEfficiency = i < efficiencyCores
                let name = isEfficiency ? "E\(i + 1)" : "P\(i - efficiencyCores + 1)"
                cores.append(CoreLoad(name: name, isPerformance: !isEfficiency, usage: usage))
            } else {
                cores.append(CoreLoad(name: "C\(i + 1)", isPerformance: true, usage: usage))
            }
        }

        var loads = [Double](repeating: 0, count: 3)
        _ = getloadavg(&loads, 3)
        let processCount = max(0, Int(proc_listallpids(nil, 0)))

        return CPUSnapshot(user: total.user, system: total.system, idle: total.idle, cores: cores,
                           performanceCores: hasLevels ? performanceCores : 0,
                           efficiencyCores: hasLevels ? efficiencyCores : 0,
                           load1: loads[0], load5: loads[1], load15: loads[2],
                           processCount: processCount, threadCount: threadCount, uptime: uptime())
    }

    var coreCount: Int { previous.count }

    private func readTicks() -> [CPUTicks]? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let kr = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
        guard kr == KERN_SUCCESS, let info else { return nil }
        defer {
            let size = vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), size)
        }
        var result: [CPUTicks] = []
        result.reserveCapacity(Int(cpuCount))
        let stride = Int(CPU_STATE_MAX)
        for i in 0..<Int(cpuCount) {
            let base = i * stride
            func tick(_ state: Int32) -> UInt64 { UInt64(UInt32(bitPattern: info[base + Int(state)])) }
            result.append(CPUTicks(user: tick(CPU_STATE_USER), system: tick(CPU_STATE_SYSTEM),
                                   idle: tick(CPU_STATE_IDLE), nice: tick(CPU_STATE_NICE)))
        }
        return result
    }

    private func uptime() -> Double {
        guard let boot = Sysctl.get("kern.boottime", timeval.self) else { return ProcessInfo.processInfo.systemUptime }
        return Date().timeIntervalSince1970 - (Double(boot.tv_sec) + Double(boot.tv_usec) / 1e6)
    }
}
#endif
