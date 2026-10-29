import Foundation

struct HistoryPoint: Identifiable, Hashable {
    let id: Int
    let date: Date
    let value: Double
}

/// Fixed-capacity time series for graphs.
struct History {
    private(set) var points: [HistoryPoint] = []
    private var nextID = 0
    var capacity: Int

    init(capacity: Int) { self.capacity = capacity }

    var last: Double? { points.last?.value }
    var values: [Double] { points.map(\.value) }
    var maxValue: Double { points.map(\.value).max() ?? 0 }

    mutating func append(_ value: Double, at date: Date) {
        points.append(HistoryPoint(id: nextID, date: date, value: value.isFinite ? value : 0))
        nextID &+= 1
        if points.count > capacity { points.removeFirst(points.count - capacity) }
    }

    /// Value of the point closest to `date`.
    func value(near date: Date) -> Double? {
        points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }?.value
    }
}
