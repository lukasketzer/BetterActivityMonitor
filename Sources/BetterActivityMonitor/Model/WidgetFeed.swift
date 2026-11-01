#if WIDGETS
import SystemKit
import WidgetKit

/// Feeds the desktop widgets while the app runs: a point a minute into their shared history, and a widget
/// refresh every few minutes so they show it. Only in the Xcode build, which has the App Group entitlement.
@MainActor
enum WidgetFeed {
    private static var lastReload: Date?

    /// Called with each finished minute of `HistoryRecorder`, so the averaging lives in one place.
    static func record(_ minute: SystemMinute, disk: Double) {
        let end = Date(timeIntervalSince1970: TimeInterval(minute.ts + 60))
        let sample = HistorySample(date: end, cpu: minute.cpu, memory: minute.memUsed, disk: disk,
                                   battery: minute.battery, gpu: minute.gpu)
        Task.detached(priority: .utility) { SharedHistory.append(sample, minimumGap: 30) }

        let now = Date()
        if lastReload.map({ now.timeIntervalSince($0) >= 5 * 60 }) ?? true {
            lastReload = now
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
#endif
