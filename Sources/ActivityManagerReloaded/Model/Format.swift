import Foundation

enum Fmt {
    private static let units = ["B", "KB", "MB", "GB", "TB", "PB"]

    static func bytes(_ value: UInt64) -> String { bytes(Double(value)) }

    static func bytes(_ value: Double) -> String {
        var v = max(value, 0)
        var unit = 0
        while v >= 1024, unit < units.count - 1 {
            v /= 1024
            unit += 1
        }
        if unit == 0 { return "\(Int(v)) B" }
        let digits = v >= 100 ? 0 : v >= 10 ? 1 : 2
        return String(format: "%.\(digits)f %@", v, units[unit])
    }

    static func rate(_ value: Double) -> String { bytes(value) + "/s" }

    /// `fraction` is 0...1.
    static func percent(_ fraction: Double, digits: Int = 1) -> String {
        String(format: "%.\(digits)f%%", fraction * 100)
    }

    static func number(_ value: Double, digits: Int = 1) -> String {
        String(format: "%.\(digits)f", value)
    }

    static func compact(_ value: Double) -> String {
        switch value {
        case 1_000_000...: String(format: "%.1fM", value / 1_000_000)
        case 10_000...: String(format: "%.0fK", value / 1000)
        case 1000...: String(format: "%.1fK", value / 1000)
        default: String(format: "%.0f", value)
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(max(seconds, 0))
        let days = s / 86400, hours = (s % 86400) / 3600, minutes = (s % 3600) / 60, secs = s % 60
        if days > 0 { return "\(days)d \(hours)h \(minutes)m" }
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// CPU time with hundredths, like Activity Monitor's "CPU Time" column.
    static func cpuTime(_ seconds: TimeInterval) -> String {
        let s = max(seconds, 0)
        let hours = Int(s) / 3600, minutes = (Int(s) % 3600) / 60
        let rest = s.truncatingRemainder(dividingBy: 60)
        if hours > 0 { return String(format: "%d:%02d:%05.2f", hours, minutes, rest) }
        return String(format: "%d:%05.2f", minutes, rest)
    }

    static func temperature(_ celsius: Double, fahrenheit: Bool) -> String {
        fahrenheit ? String(format: "%.0f°F", celsius * 9 / 5 + 32) : String(format: "%.0f°C", celsius)
    }

    static func minutes(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    static let startDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .medium
        return f
    }()
}
