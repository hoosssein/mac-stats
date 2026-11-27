import Foundation

/// Model layer: turns numbers into the short strings used in the menu bar and menus.
/// Matches the wireframe: "23%", "17.0 GB", "412 GB", "1.38 TB", "320 KB/s", "1.2 MB/s".
public struct UnitFormatter: Sendable {
    public var units: Units

    public init(units: Units = .base1000) { self.units = units }

    private var base: Double { units == .base1024 ? 1024 : 1000 }
    private var infix: String { units == .base1024 ? "i" : "" }

    public func percent(_ v: Double) -> String {
        guard v.isFinite else { return "–" }
        return "\(Int(v.rounded()))%"
    }

    /// Percent of one core with one decimal, for process lists ("48.2%").
    public func processPercent(_ v: Double) -> String {
        guard v.isFinite else { return "–" }
        return String(format: "%.1f%%", v)
    }

    /// Sizes: below 1 KB "512 B", then KB, MB, GB (one decimal under 100), TB with two decimals.
    public func bytes(_ b: Double) -> String {
        guard b.isFinite else { return "–" }
        let k = base
        let v = max(0, b)
        if v < k { return "\(Int(v)) B" }
        if v < k * k { return "\(Int((v / k).rounded())) K\(infix)B" }
        if v < k * k * k {
            let mb = v / (k * k)
            return mb < 10 ? String(format: "%.1f M\(infix)B", mb) : "\(Int(mb.rounded())) M\(infix)B"
        }
        if v < k * k * k * k {
            let gb = v / (k * k * k)
            return gb < 100 ? String(format: "%.1f G\(infix)B", gb) : "\(Int(gb.rounded())) G\(infix)B"
        }
        return String(format: "%.2f T\(infix)B", v / (k * k * k * k))
    }

    /// Byte rates. Network rates switch to bits when the units setting says so.
    public func rate(_ bytesPerSecond: Double, network: Bool = false) -> String {
        guard bytesPerSecond.isFinite else { return "–" }
        let v = max(0, bytesPerSecond)
        if network && units == .bitsForNetwork {
            let bits = v * 8
            if bits < 1e6 { return "\(Int((bits / 1e3).rounded())) Kb/s" }
            if bits < 1e9 { return bits < 1e7 ? String(format: "%.1f Mb/s", bits / 1e6) : "\(Int((bits / 1e6).rounded())) Mb/s" }
            return String(format: "%.1f Gb/s", bits / 1e9)
        }
        let k = base
        if v < k * k { return "\(Int((v / k).rounded())) K\(infix)B/s" }
        if v < k * k * k {
            let mb = v / (k * k)
            return mb < 10 ? String(format: "%.1f M\(infix)B/s", mb) : "\(Int(mb.rounded())) M\(infix)B/s"
        }
        return String(format: "%.1f G\(infix)B/s", v / (k * k * k))
    }

    /// Scale labels inside charts: short and without trailing zeros ("5 MB/s", "32 GB", "1 TB").
    public func axisRate(_ bytesPerSecond: Double, network: Bool = false) -> String {
        if bytesPerSecond <= 0 { return "0" }
        if network && units == .bitsForNetwork {
            let bits = bytesPerSecond * 8
            if bits >= 1e9 { return "\(trim(bits / 1e9)) Gb/s" }
            if bits >= 1e6 { return "\(trim(bits / 1e6)) Mb/s" }
            return "\(trim(bits / 1e3)) Kb/s"
        }
        let k = base
        if bytesPerSecond >= k * k * k { return "\(trim(bytesPerSecond / (k * k * k))) G\(infix)B/s" }
        if bytesPerSecond >= k * k { return "\(trim(bytesPerSecond / (k * k))) M\(infix)B/s" }
        return "\(trim(bytesPerSecond / k)) K\(infix)B/s"
    }

    public func axisBytes(_ b: Double) -> String {
        if b <= 0 { return "0" }
        let k = base
        if b >= k * k * k * k { return "\(trim(b / (k * k * k * k))) T\(infix)B" }
        if b >= k * k * k { return "\(trim(b / (k * k * k))) G\(infix)B" }
        if b >= k * k { return "\(trim(b / (k * k))) M\(infix)B" }
        return "\(trim(b / k)) K\(infix)B"
    }

    public func axisPercent(_ v: Double) -> String { "\(trim(v))%" }

    public func count(_ v: Double) -> String {
        if v >= 1e6 { return String(format: "%.1f M", v / 1e6) }
        if v >= 1e4 { return "\(Int((v / 1e3).rounded())) K" }
        let n = Int(v.rounded())
        return n >= 1000 ? "\(n / 1000),\(String(format: "%03d", n % 1000))" : "\(n)"
    }

    private func trim(_ v: Double) -> String {
        let r = (v * 10).rounded() / 10
        return r == r.rounded() ? "\(Int(r))" : String(format: "%.1f", r)
    }
}
