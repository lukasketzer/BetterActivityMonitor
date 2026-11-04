import Foundation

/// How often each kind of desktop widget asked to be updated, shared through the App Group. A widget's own
/// timeline is only a hint WidgetKit stretches, so the running app reads this and pushes reloads at that pace.
public enum WidgetRefreshBoard {
    public static let appGroup = "7HGU5XLVZH.dev.lukas.BetterActivityMonitor"
    private static let key = "widgetRefreshRequests"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    /// Called by a widget each time it builds a timeline.
    public static func record(kind: String, seconds: TimeInterval, now: Date = .now) {
        guard let defaults else { return }
        var all = defaults.dictionary(forKey: key) as? [String: [String: Double]] ?? [:]
        all[kind, default: [:]][String(Int(seconds))] = now.timeIntervalSince1970
        defaults.set(all, forKey: key)
    }

    /// The fastest pace a live widget of each kind asked for. A widget re-records on every update, so a request
    /// that hasn't been repeated for a few of its own intervals belongs to a removed or re-set widget and drops out.
    public static func intervals(now: Date = .now) -> [String: TimeInterval] {
        guard let all = defaults?.dictionary(forKey: key) as? [String: [String: Double]] else { return [:] }
        let t = now.timeIntervalSince1970
        return all.compactMapValues { requests in
            requests.compactMap { seconds, seen -> TimeInterval? in
                guard let s = TimeInterval(seconds), t - seen < max(3 * s, 120) else { return nil }
                return s
            }
            .min()
        }
    }
}
