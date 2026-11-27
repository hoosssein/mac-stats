#if os(macOS)
import Darwin
import Foundation
import StatsCore
import SystemConfiguration

/// Data layer: per-interface byte counters from `sysctl NET_RT_IFLIST2` (64-bit, no 4 GB wrap).
final class NetworkCollector {
    private struct Counters { var inBytes: UInt64; var outBytes: UInt64 }

    private var previous: [String: Counters] = [:]
    private var previousTime: Double = 0
    private var displayNames: [String: String] = [:]
    private var namesLoadedAt: Double = -1_000

    // "Today" totals, counted while the app runs.
    private var dayStart = Calendar.current.startOfDay(for: Date())
    private var todayIn: Double = 0
    private var todayOut: Double = 0
    private var peakToday: Double = 0
    private var peakTodayAt: Double = 0

    func sample() -> NetworkSnapshot? {
        let now = monotonicSeconds()
        guard let raw = readCounters() else { return nil }
        let addresses = readIPv4()
        if now - namesLoadedAt > 60 { loadDisplayNames(); namesLoadedAt = now }

        let dt = previousTime > 0 ? now - previousTime : 0
        var interfaces: [InterfaceStat] = []
        for (name, entry) in raw.sorted(by: { $0.key < $1.key }) {
            var down = 0.0, up = 0.0
            if dt > 0, let p = previous[name] {
                // A smaller value means the interface was reset; count nothing for this round.
                down = entry.counters.inBytes >= p.inBytes ? Double(entry.counters.inBytes - p.inBytes) / dt : 0
                up = entry.counters.outBytes >= p.outBytes ? Double(entry.counters.outBytes - p.outBytes) / dt : 0
            }
            let tunnel = name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp")
            // Show interfaces that are up and have moved data or have an address.
            guard entry.counters.inBytes + entry.counters.outBytes > 0 || addresses[name] != nil else { continue }
            interfaces.append(InterfaceStat(
                bsdName: name, displayName: displayName(for: name), ipv4: addresses[name],
                downBps: down, upBps: up, linkBitsPerSecond: Double(entry.baud),
                totalIn: Double(entry.counters.inBytes), totalOut: Double(entry.counters.outBytes), isTunnel: tunnel))
        }
        let firstSample = previousTime == 0
        previous = raw.mapValues(\.counters)
        previousTime = now
        if firstSample { return nil }

        // Today's totals and peak (physical interfaces only).
        let today = Calendar.current.startOfDay(for: Date())
        if today != dayStart { dayStart = today; todayIn = 0; todayOut = 0; peakToday = 0; peakTodayAt = 0 }
        let physical = interfaces.filter { !$0.isTunnel }
        let down = physical.reduce(0) { $0 + $1.downBps }, up = physical.reduce(0) { $0 + $1.upBps }
        todayIn += down * dt
        todayOut += up * dt
        if down > peakToday { peakToday = down; peakTodayAt = Date().timeIntervalSince1970 }

        return NetworkSnapshot(interfaces: interfaces, todayIn: todayIn, todayOut: todayOut,
                               peakToday: peakToday, peakTodayAt: peakTodayAt)
    }

    private func readCounters() -> [String: (counters: Counters, baud: UInt64)]? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len = 0
        guard sysctl(&mib, u_int(mib.count), nil, &len, nil, 0) == 0, len > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, u_int(mib.count), &buf, &len, nil, 0) == 0 else { return nil }

        var result: [String: (counters: Counters, baud: UInt64)] = [:]
        buf.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= len {
                let hdr = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let msgLen = Int(hdr.ifm_msglen)
                guard msgLen > 0 else { break }
                if Int32(hdr.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= len {
                    let ifm = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    let isUp = (ifm.ifm_flags & IFF_UP) != 0
                    let isLoopback = (ifm.ifm_flags & IFF_LOOPBACK) != 0
                    if isUp && !isLoopback, let name = interfaceName(Int(ifm.ifm_index)) {
                        result[name] = (Counters(inBytes: ifm.ifm_data.ifi_ibytes, outBytes: ifm.ifm_data.ifi_obytes),
                                        ifm.ifm_data.ifi_baudrate)
                    }
                }
                offset += msgLen
            }
        }
        return result
    }

    private func interfaceName(_ index: Int) -> String? {
        var buf = [CChar](repeating: 0, count: Int(IF_NAMESIZE) + 1)
        guard if_indextoname(UInt32(index), &buf) != nil else { return nil }
        return String(cString: buf)
    }

    private func readIPv4() -> [String: String] {
        var result: [String: String] = [:]
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return result }
        defer { freeifaddrs(list) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = cursor {
            defer { cursor = ifa.pointee.ifa_next }
            guard let addr = ifa.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: ifa.pointee.ifa_name)
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                result[name] = String(cString: host)
            }
        }
        return result
    }

    private func loadDisplayNames() {
        var names: [String: String] = [:]
        if let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] {
            for i in all {
                if let bsd = SCNetworkInterfaceGetBSDName(i) as String?,
                   let display = SCNetworkInterfaceGetLocalizedDisplayName(i) as String? {
                    names[bsd] = display
                }
            }
        }
        displayNames = names
    }

    private func displayName(for bsd: String) -> String {
        if let n = displayNames[bsd] { return n }
        if bsd.hasPrefix("utun") || bsd.hasPrefix("ipsec") { return "VPN" }
        if bsd.hasPrefix("awdl") { return "AirDrop" }
        if bsd.hasPrefix("llw") { return "Low-latency Wi-Fi" }
        if bsd.hasPrefix("bridge") { return "Bridge" }
        return bsd
    }
}
#endif
