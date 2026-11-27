import Foundation

/// Model layer: time text for chart tooltips ("14:29:56", "Thu 16:10", "Tue 24 Nov · 09:00")
/// and "how long ago" text ("2 min 4 s ago").
public enum TimeLabels {
    private static let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// The time of a point, formatted for the chart period it belongs to.
    public static func when(_ date: Date, range: ChartRange, now: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: date)
        let hm = two(c.hour ?? 0) + ":" + two(c.minute ?? 0)
        if range.seconds <= 3600 { return hm + ":" + two(c.second ?? 0) }
        let weekday = days[((c.weekday ?? 1) - 1 + 7) % 7]
        if range.seconds <= 86_400 {
            return calendar.isDate(date, inSameDayAs: now) ? hm : weekday + " " + hm
        }
        let month = months[((c.month ?? 1) - 1 + 12) % 12]
        return "\(weekday) \(c.day ?? 1) \(month) · \(hm)"
    }

    /// "now", "45 s ago", "2 min 4 s ago", "23 min ago", "3 h 10 min ago", "2 d 4 h ago".
    public static func ago(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        if s < 1 { return "now" }
        if s < 60 { return "\(s) s ago" }
        if s < 600 { return "\(s / 60) min \(s % 60) s ago" }
        if s < 3600 { return "\(Int((Double(s) / 60).rounded())) min ago" }
        if s < 86_400 { return "\(s / 3600) h \((s % 3600) / 60) min ago" }
        return "\(s / 86_400) d \((s % 86_400) / 3600) h ago"
    }

    /// Uptime text: "6 d 3 h", "5 h 12 min", "8 min".
    public static func duration(_ seconds: Double) -> String {
        let s = Int(max(0, seconds))
        if s >= 86_400 { return "\(s / 86_400) d \((s % 86_400) / 3600) h" }
        if s >= 3600 { return "\(s / 3600) h \((s % 3600) / 60) min" }
        return "\(max(1, s / 60)) min"
    }

    /// Clock time "10:12".
    public static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return two(c.hour ?? 0) + ":" + two(c.minute ?? 0)
    }

    private static func two(_ v: Int) -> String { v < 10 ? "0\(v)" : "\(v)" }
}
