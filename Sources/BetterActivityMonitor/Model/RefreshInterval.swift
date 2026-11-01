import Foundation

/// The update interval in milliseconds, like btop's `- 1000ms +`. Stored in seconds under
/// `SettingsKey.refreshInterval`, as before.
enum RefreshInterval {
    static let range = 100...10_000

    static func clamped(_ ms: Int) -> Int { min(max(ms, range.lowerBound), range.upperBound) }

    /// One click of − / +: 100 ms steps below a second, 500 ms steps above, landing on that grid.
    static func step(_ ms: Int, faster: Bool) -> Int {
        let next: Int
        if faster {
            next = ms > 1000 ? max((ms - 1) / 500 * 500, 1000) : (ms - 1) / 100 * 100
        } else {
            next = ms >= 1000 ? ms / 500 * 500 + 500 : ms / 100 * 100 + 100
        }
        return clamped(next)
    }

    /// Parses what the user typed: "250", "250 ms", "1.5s", "2 s". Nil if it isn't a number.
    static func parse(_ text: String) -> Int? {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        if t.hasSuffix("ms"), let v = Double(t.dropLast(2).trimmingCharacters(in: .whitespaces)) { return clamped(Int(v.rounded())) }
        if t.hasSuffix("s"), let v = Double(t.dropLast().trimmingCharacters(in: .whitespaces)) { return clamped(Int((v * 1000).rounded())) }
        if let v = Double(t) { return clamped(Int(v.rounded())) }
        return nil
    }

    static var milliseconds: Int { Int((Defaults.refreshInterval * 1000).rounded()) }

    static func set(_ ms: Int, _ defaults: UserDefaults = .standard) {
        defaults.set(Double(clamped(ms)) / 1000, forKey: SettingsKey.refreshInterval)
    }
}

extension UserDefaults {
    /// KVO-observable mirror of the setting; the name must match `SettingsKey.refreshInterval`.
    @objc dynamic var refreshInterval: Double { double(forKey: SettingsKey.refreshInterval) }
}
