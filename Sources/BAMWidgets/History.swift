import Foundation
import SystemKit

extension HistorySample {
    func value(for metric: WidgetMetric) -> Double? {
        switch metric {
        case .cpu: return cpu
        case .memory: return memory
        case .disk: return disk
        case .battery: return battery
        case .gpu: return gpu
        }
    }
}

/// The widgets' view of `SharedHistory`: the app fills it every minute while running, and each widget refresh
/// adds a point too so graphs keep going when the app is quit.
enum HistoryStore {
    static func load() -> [HistorySample] { SharedHistory.load() }

    static func record(_ entry: SystemEntry) {
        let sample = HistorySample(date: entry.date, cpu: entry.cpu, memory: entry.memFraction,
                                   disk: entry.mainVolume?.usedFraction ?? 0, battery: entry.battery?.charge,
                                   gpu: entry.gpu)
        SharedHistory.append(sample, minimumGap: 5 * 60)
    }

    /// Plausible-looking data for the widget gallery and Xcode previews.
    static let placeholder: [HistorySample] = (0..<96).map { i in
        let x = Double(i)
        return HistorySample(
            date: .now.addingTimeInterval(-Double(95 - i) * 15 * 60),
            cpu: max(0.03, 0.22 + 0.14 * sin(x / 5) + 0.07 * sin(x * 1.7)),
            memory: 0.52 + 0.06 * sin(x / 11) + 0.02 * sin(x * 2),
            disk: 0.38 + x * 0.0004,
            battery: max(0.1, 1 - x * 0.0045),
            gpu: max(0.02, 0.3 + 0.25 * sin(x / 7) + 0.1 * sin(x * 1.3))
        )
    }
}
