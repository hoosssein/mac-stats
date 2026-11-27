import Foundation

// Model layer: history storage. See docs/kb/architecture.md "History".

/// A fixed-capacity buffer that drops the oldest element when full.
public struct RingBuffer<Element: Sendable>: Sendable {
    public let capacity: Int
    private var storage: [Element] = []
    private var head = 0  // index of the oldest element once full

    public init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    public var count: Int { storage.count }
    public var isEmpty: Bool { storage.isEmpty }

    public mutating func append(_ e: Element) {
        if storage.count < capacity {
            storage.append(e)
        } else {
            storage[head] = e
            head = (head + 1) % capacity
        }
    }

    public mutating func removeAll() {
        storage.removeAll(keepingCapacity: false)
        head = 0
    }

    /// Elements from oldest to newest.
    public var elements: [Element] {
        storage.count < capacity ? storage : Array(storage[head...] + storage[..<head])
    }

    public var last: Element? {
        guard !storage.isEmpty else { return nil }
        return storage.count < capacity ? storage.last : storage[(head - 1 + capacity) % capacity]
    }

    /// The newest `n` elements, oldest first.
    public func suffix(_ n: Int) -> [Element] {
        let all = elements
        return Array(all.suffix(n))
    }
}

/// One history bucket: min, average and max of the samples that fell into it.
public struct Bucket: Codable, Sendable, Equatable {
    /// Start time of the bucket, seconds since 1970.
    public var t: Double
    public var min: Float
    public var max: Float
    public var sum: Float
    public var count: Int32

    public var avg: Double { count > 0 ? Double(sum) / Double(count) : 0 }

    public init(t: Double, value: Double) {
        self.t = t; min = Float(value); max = Float(value); sum = Float(value); count = 1
    }

    public init(t: Double, min: Float, max: Float, sum: Float, count: Int32) {
        self.t = t; self.min = min; self.max = max; self.sum = sum; self.count = count
    }

    mutating func add(_ value: Double) {
        let v = Float(value)
        if v < min { min = v }
        if v > max { max = v }
        sum += v
        count += 1
    }

    mutating func merge(_ b: Bucket) {
        if b.min < min { min = b.min }
        if b.max > max { max = b.max }
        sum += b.sum
        count += b.count
    }
}

/// A point to draw: the time and the min, average and max of the merged buckets.
public struct ChartPoint: Sendable, Equatable {
    public var t: Double
    public var min: Double
    public var avg: Double
    public var max: Double

    public init(t: Double, min: Double, avg: Double, max: Double) {
        self.t = t; self.min = min; self.avg = avg; self.max = max
    }
}

public struct TierSpec: Sendable, Equatable {
    public let step: Double
    public let keep: Double
    public var capacity: Int { Int((keep / step).rounded(.up)) }
}

/// One series with four tiers: raw 1 s for 1 h, 10 s for 24 h, 1 min for 7 d, 5 min for `keepDays`.
public struct TieredSeries: Sendable {
    public static func specs(keepDays: Int) -> [TierSpec] {
        [TierSpec(step: 1, keep: 3600),
         TierSpec(step: 10, keep: 86_400),
         TierSpec(step: 60, keep: 604_800),
         TierSpec(step: 300, keep: Double(max(1, keepDays)) * 86_400)]
    }

    public let specs: [TierSpec]
    private var completed: [RingBuffer<Bucket>]
    private var open: [Bucket?]

    public init(keepDays: Int = 30) {
        specs = TieredSeries.specs(keepDays: keepDays)
        completed = specs.map { RingBuffer<Bucket>(capacity: $0.capacity) }
        open = Array(repeating: nil, count: specs.count)
    }

    public mutating func append(_ value: Double, at t: Double) {
        guard value.isFinite else { return }
        for i in specs.indices {
            let start = (t / specs[i].step).rounded(.down) * specs[i].step
            if var b = open[i], b.t == start {
                b.add(value)
                open[i] = b
            } else {
                if let b = open[i] { completed[i].append(b) }
                open[i] = Bucket(t: start, value: value)
            }
        }
    }

    /// All buckets of a tier, oldest first, including the open (current) one.
    public func buckets(tier: Int) -> [Bucket] {
        var all = completed[tier].elements
        if let b = open[tier] { all.append(b) }
        return all
    }

    /// Completed buckets of a tier that start after `t` (for saving to disk).
    public func completedBuckets(tier: Int, after t: Double) -> [Bucket] {
        completed[tier].elements.filter { $0.t > t }
    }

    /// Loads saved buckets into a tier. Buckets must be oldest first and older than anything already recorded.
    public mutating func restore(tier: Int, buckets: [Bucket]) {
        guard specs.indices.contains(tier) else { return }
        let existing = completed[tier].elements
        var ring = RingBuffer<Bucket>(capacity: specs[tier].capacity)
        let firstExisting = existing.first?.t ?? open[tier]?.t ?? .infinity
        for b in buckets where b.t < firstExisting { ring.append(b) }
        for b in existing { ring.append(b) }
        completed[tier] = ring
    }

    /// The newest values of the raw tier (averages), oldest first. Used for menu bar sparklines.
    public func recent(_ n: Int) -> [Double] {
        buckets(tier: 0).suffix(n).map(\.avg)
    }

    public var latest: Double? { open[0]?.avg ?? completed[0].last?.avg }

    /// Points for a chart period, merged so there are at most `maxPoints`.
    public func points(range: ChartRange, now: Double, maxPoints: Int = 300) -> [ChartPoint] {
        let from = now - range.seconds
        let step = specs[range.tier].step
        let src = buckets(tier: range.tier).filter { $0.t + step > from && $0.t <= now }
        return TieredSeries.downsample(src, from: from, to: now, maxPoints: maxPoints)
    }

    /// Merges buckets into at most `maxPoints` time slots of equal width between `from` and `to`.
    public static func downsample(_ buckets: [Bucket], from: Double, to: Double, maxPoints: Int) -> [ChartPoint] {
        guard !buckets.isEmpty else { return [] }
        if buckets.count <= maxPoints {
            return buckets.map { ChartPoint(t: $0.t, min: Double($0.min), avg: $0.avg, max: Double($0.max)) }
        }
        let width = Swift.max((to - from) / Double(maxPoints), 1e-9)
        var out: [ChartPoint] = []
        var cur: Bucket?
        var slot = -1
        for b in buckets {
            let s = Int(((b.t - from) / width).rounded(.down))
            if s != slot, let c = cur {
                out.append(ChartPoint(t: c.t, min: Double(c.min), avg: c.avg, max: Double(c.max)))
                cur = nil
            }
            slot = s
            if cur == nil { cur = b } else { cur!.merge(b) }
        }
        if let c = cur { out.append(ChartPoint(t: c.t, min: Double(c.min), avg: c.avg, max: Double(c.max))) }
        return out
    }
}

/// All series of the app, keyed like "cpu.usr" (item id + "." + series key).
public struct HistoryStore: Sendable {
    public private(set) var series: [String: TieredSeries] = [:]
    public private(set) var keepDays: Int

    public init(keepDays: Int = 30) { self.keepDays = keepDays }

    public static func key(item: String, series: String) -> String { item + "." + series }

    public mutating func record(_ values: [String: Double], at t: Double) {
        for (k, v) in values {
            if series[k] == nil { series[k] = TieredSeries(keepDays: keepDays) }
            series[k]!.append(v, at: t)
        }
    }

    public func points(_ key: String, range: ChartRange, now: Double, maxPoints: Int = 300) -> [ChartPoint] {
        series[key]?.points(range: range, now: now, maxPoints: maxPoints) ?? []
    }

    public func recent(_ key: String, count: Int) -> [Double] {
        series[key]?.recent(count) ?? []
    }

    public func latest(_ key: String) -> Double? { series[key]?.latest }

    public mutating func removeAll() { series.removeAll() }

    /// Changing how long to keep history keeps the data that still fits.
    public mutating func setKeepDays(_ days: Int) {
        guard days != keepDays else { return }
        keepDays = days
        var next: [String: TieredSeries] = [:]
        for (k, s) in series {
            var n = TieredSeries(keepDays: days)
            for tier in 0..<s.specs.count { n.restore(tier: tier, buckets: s.buckets(tier: tier)) }
            next[k] = n
        }
        series = next
    }

    public mutating func restore(key: String, tier: Int, buckets: [Bucket]) {
        if series[key] == nil { series[key] = TieredSeries(keepDays: keepDays) }
        series[key]!.restore(tier: tier, buckets: buckets)
    }
}

/// Short per-app histories for sparklines in lists. In memory only.
public struct AppSparkStore: Sendable {
    public var capacity: Int
    private var values: [String: RingBuffer<Double>] = [:]
    private var lastSeen: [String: Int] = [:]
    private var tick = 0

    public init(capacity: Int) { self.capacity = max(2, capacity) }

    /// Records one value per app. Apps not seen for `capacity` rounds are dropped.
    public mutating func record(_ entries: [String: Double], keepTop: Int = 20) {
        tick += 1
        let top = entries.sorted { $0.value > $1.value }.prefix(keepTop)
        for (name, v) in top {
            if values[name] == nil { values[name] = RingBuffer(capacity: capacity) }
            values[name]!.append(v)
            lastSeen[name] = tick
        }
        for (name, seen) in lastSeen where tick - seen > capacity {
            values[name] = nil
            lastSeen[name] = nil
        }
    }

    public func series(_ name: String) -> [Double] { values[name]?.elements ?? [] }

    public mutating func removeAll() { values.removeAll(); lastSeen.removeAll() }
}
