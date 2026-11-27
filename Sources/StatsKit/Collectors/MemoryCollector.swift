#if os(macOS)
import Darwin
import Foundation
import StatsCore

/// Data layer: memory totals from `host_statistics64(HOST_VM_INFO64)` and sysctl.
final class MemoryCollector {
    private let host = mach_host_self()
    private let total = Double(Sysctl.get("hw.memsize", UInt64.self) ?? 0)
    private let pageSize = Double(vm_kernel_page_size)

    func sample() -> MemorySnapshot? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }

        let ps = pageSize
        let app = max(0, Double(stats.internal_page_count) - Double(stats.purgeable_count)) * ps
        let wired = Double(stats.wire_count) * ps
        let compressed = Double(stats.compressor_page_count) * ps
        let cached = (Double(stats.external_page_count) + Double(stats.purgeable_count)) * ps
        let free = Double(stats.free_count) * ps

        let level = Sysctl.int("kern.memorystatus_vm_pressure_level").flatMap { PressureLevel(rawValue: $0) } ?? .normal
        let freePercent = Sysctl.int("kern.memorystatus_level")
        let swap = Sysctl.get("vm.swapusage", xsw_usage.self)

        return MemorySnapshot(
            total: total, app: app, wired: wired, compressed: compressed, cached: cached, free: free,
            pressure: level, pressurePercent: freePercent.map { Double(max(0, min(100, 100 - $0))) },
            swapUsed: Double(swap?.xsu_used ?? 0), swapTotal: Double(swap?.xsu_total ?? 0),
            pageIns: Double(stats.pageins), pageOuts: Double(stats.pageouts),
            swapIns: Double(stats.swapins), swapOuts: Double(stats.swapouts),
            compressions: Double(stats.compressions), decompressions: Double(stats.decompressions))
    }
}
#endif
