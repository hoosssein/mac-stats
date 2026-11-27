#if os(macOS)
import Darwin
import Foundation

/// Data layer: small helpers for `sysctlbyname` and Mach time.
enum Sysctl {
    /// Reads a fixed-size value (Int32, UInt64, a C struct, ...). Returns nil on error or size mismatch.
    static func get<T>(_ name: String, _ type: T.Type) -> T? {
        var size = MemoryLayout<T>.size
        let ptr = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<T>.alignment)
        defer { ptr.deallocate() }
        guard sysctlbyname(name, ptr, &size, nil, 0) == 0, size == MemoryLayout<T>.size else { return nil }
        return ptr.load(as: T.self)
    }

    /// Reads an integer that may be 32 or 64 bits wide.
    static func int(_ name: String) -> Int? {
        var size = 8
        var buf = [UInt8](repeating: 0, count: 8)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        switch size {
        case 4: return Int(buf.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) })
        case 8: return Int(buf.withUnsafeBytes { $0.loadUnaligned(as: Int64.self) })
        default: return nil
        }
    }
}

enum MachTime {
    /// Converts Mach absolute time units to nanoseconds (Apple silicon uses 125/3).
    static let nanosPerTick: Double = {
        var info = mach_timebase_info_data_t()
        guard mach_timebase_info(&info) == KERN_SUCCESS, info.denom != 0 else { return 1 }
        return Double(info.numer) / Double(info.denom)
    }()
}

/// Monotonic seconds, for rate math (not affected by clock changes).
func monotonicSeconds() -> Double { ProcessInfo.processInfo.systemUptime }
#endif
