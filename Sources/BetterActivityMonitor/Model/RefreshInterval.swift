import Foundation

/// The update interval in milliseconds, like btop's `- 1000ms +`. Stored in seconds under
/// `SettingsKey.refreshInterval`, as before.
enum RefreshInterval {
    /// The choices offered in the View menu and in Settings.
    static let presets = [500, 1_000, 2_000, 5_000, 10_000, 30_000, 60_000]
    static let range = presets.first!...presets.last!

    static func clamped(_ ms: Int) -> Int { min(max(ms, range.lowerBound), range.upperBound) }

    /// The preset closest to `ms`, so an old stored value still shows a selection.
    static func nearestPreset(_ ms: Int) -> Int { presets.min { abs($0 - ms) < abs($1 - ms) }! }

    static func label(_ ms: Int) -> String {
        ms < 1000 ? "\(ms) ms" : ms < 60_000 ? "\(ms / 1000) s" : "\(ms / 60_000) min"
    }

    /// One step to the next faster or slower preset, for ⌘+ / ⌘−.
    static func step(_ ms: Int, faster: Bool) -> Int {
        let i = presets.firstIndex(of: nearestPreset(ms))!
        return presets[min(max(i + (faster ? -1 : 1), 0), presets.count - 1)]
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
