#if WIDGETS
import SystemKit
import WidgetKit

/// Feeds the desktop widgets while the app runs: a point a minute into their shared history, and a widget
/// refresh every few minutes so they show it. Only in the Xcode build, which has the App Group entitlement.
@MainActor
enum WidgetFeed {
    private static var lastSample: Date?
    private static var lastReload: Date?

    static func record(_ s: SystemSnapshot, cpuHistory: History, gpuHistory: History) {
        let now = s.timestamp
        if let lastSample, now.timeIntervalSince(lastSample) < 60 { return }
        lastSample = now

        // Average over the minute, so a graph bar isn't just whatever the last tick was.
        func minuteAverage(_ history: History, current: Double?) -> Double? {
            let recent = history.points.filter { now.timeIntervalSince($0.date) < 60 }.map(\.value)
            return recent.isEmpty ? current : recent.reduce(0, +) / Double(recent.count)
        }
        let cpu = minuteAverage(cpuHistory, current: s.cpu.total) ?? 0
        let gpu = s.gpu == nil ? nil : minuteAverage(gpuHistory, current: s.gpu?.utilization)
        let disk = s.disks.volumes.first { $0.path == "/" }?.usedFraction ?? 0
        let sample = HistorySample(date: now, cpu: cpu, memory: s.memory.usedFraction, disk: disk,
                                   battery: s.battery?.charge, gpu: gpu)
        Task.detached(priority: .utility) { SharedHistory.append(sample, minimumGap: 30) }

        if lastReload.map({ now.timeIntervalSince($0) >= 5 * 60 }) ?? true {
            lastReload = now
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
#endif
