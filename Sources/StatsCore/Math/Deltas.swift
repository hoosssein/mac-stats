import Foundation

// Model layer: counter math used by the collectors. Pure functions, unit tested.

public enum Counter {
    /// Difference between two readings of a counter that wraps at 2^bits.
    /// A smaller new value means the counter wrapped once.
    public static func delta(_ old: UInt64, _ new: UInt64, bits: Int = 64) -> UInt64 {
        if new >= old { return new - old }
        if bits >= 64 { return (UInt64.max - old) &+ new &+ 1 }
        let modulus = UInt64(1) << UInt64(bits)
        return (modulus - old) + new
    }

    /// Bytes (or events) per second. Returns 0 for a zero or negative interval.
    public static func rate(_ delta: UInt64, seconds: Double) -> Double {
        seconds > 0 ? Double(delta) / seconds : 0
    }
}

/// CPU tick counters for one core, as `host_processor_info` reports them (32-bit, wrapping).
public struct CPUTicks: Sendable, Equatable {
    public var user: UInt64
    public var system: UInt64
    public var idle: UInt64
    public var nice: UInt64

    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user; self.system = system; self.idle = idle; self.nice = nice
    }

    public static func + (a: CPUTicks, b: CPUTicks) -> CPUTicks {
        CPUTicks(user: a.user &+ b.user, system: a.system &+ b.system, idle: a.idle &+ b.idle, nice: a.nice &+ b.nice)
    }
}

public struct CPUUsage: Sendable, Equatable {
    /// Percent, 0–100. Nice time counts as user time.
    public var user: Double
    public var system: Double
    public var idle: Double

    public var total: Double { user + system }

    public init(user: Double, system: Double, idle: Double) {
        self.user = user; self.system = system; self.idle = idle
    }

    /// Usage between two readings of the same core. Uses 32-bit wraparound per field.
    public static func between(_ a: CPUTicks, _ b: CPUTicks, bits: Int = 32) -> CPUUsage {
        let u = Double(Counter.delta(a.user, b.user, bits: bits) + Counter.delta(a.nice, b.nice, bits: bits))
        let s = Double(Counter.delta(a.system, b.system, bits: bits))
        let i = Double(Counter.delta(a.idle, b.idle, bits: bits))
        let sum = u + s + i
        guard sum > 0 else { return CPUUsage(user: 0, system: 0, idle: 100) }
        return CPUUsage(user: u / sum * 100, system: s / sum * 100, idle: i / sum * 100)
    }

    /// Average usage over many cores (each core weighted by its ticks).
    public static func average(_ pairs: [(CPUTicks, CPUTicks)], bits: Int = 32) -> CPUUsage {
        var u = 0.0, s = 0.0, i = 0.0
        for (a, b) in pairs {
            u += Double(Counter.delta(a.user, b.user, bits: bits) + Counter.delta(a.nice, b.nice, bits: bits))
            s += Double(Counter.delta(a.system, b.system, bits: bits))
            i += Double(Counter.delta(a.idle, b.idle, bits: bits))
        }
        let sum = u + s + i
        guard sum > 0 else { return CPUUsage(user: 0, system: 0, idle: 100) }
        return CPUUsage(user: u / sum * 100, system: s / sum * 100, idle: i / sum * 100)
    }
}

public enum Scale {
    /// Rounds up to 1, 2 or 5 × 10^n. Used for chart scale maximums.
    public static func niceMax(_ value: Double) -> Double {
        guard value > 0, value.isFinite else { return 1 }
        let e = pow(10, floor(log10(value)))
        let f = value / e
        let n: Double = f <= 1 ? 1 : f <= 2 ? 2 : f <= 5 ? 5 : 10
        return n * e
    }
}
