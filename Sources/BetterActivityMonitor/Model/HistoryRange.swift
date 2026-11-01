import Foundation
import SystemKit

/// What the resource pages' charts show: the live in-memory graphs, or a span of the minute history.
enum HistoryRange: String, CaseIterable, Identifiable {
    case live = "Live", hour = "1h", day = "24h", week = "7d", month = "30d"
    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .live: 0
        case .hour: 3600
        case .day: 86_400
        case .week: 7 * 86_400
        case .month: 30 * 86_400
        }
    }

    /// Seconds per point: whole minutes, about 360 points per chart.
    var bucket: Int { max(Int(seconds / 360) / 60 * 60, 60) }
}

/// One loaded range of history, read off the main thread.
struct HistoryData {
    var series: [HistoryMetric: [HistoryValue]] = [:]
    var minutes = 0

    subscript(_ metric: HistoryMetric) -> [HistoryValue] { series[metric] ?? [] }

    static func load(from store: HistoryDatabase, metrics: [HistoryMetric], range: ClosedRange<Date>,
                     bucket: Int) async -> HistoryData {
        var data = HistoryData()
        for metric in metrics {
            data.series[metric] = await store.series(metric, from: range.lowerBound, to: range.upperBound, bucket: bucket)
        }
        data.minutes = await store.minuteCount()
        return data
    }
}
