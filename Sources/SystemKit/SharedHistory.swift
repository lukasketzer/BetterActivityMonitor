import Foundation

/// One point of the day of history the desktop widgets graph.
public struct HistorySample: Codable, Hashable, Sendable {
    public var date: Date
    public var cpu: Double      // 0...1
    public var memory: Double   // 0...1
    public var disk: Double     // 0...1, startup disk
    public var battery: Double? // 0...1
    public var gpu: Double?     // 0...1

    public init(date: Date, cpu: Double, memory: Double, disk: Double, battery: Double?, gpu: Double? = nil) {
        self.date = date
        self.cpu = cpu
        self.memory = memory
        self.disk = disk
        self.battery = battery
        self.gpu = gpu
    }
}

/// History shared between the app and its widget extension through their App Group container. The app adds a
/// point a minute while it runs; the widget adds one on each refresh, so graphs keep going when the app is quit.
public enum SharedHistory {
    public static let groupID = "7HGU5XLVZH.dev.lukas.BetterActivityMonitor"
    public static let window: TimeInterval = 24 * 3600

    private static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent("history.json")
    }

    public static func load() -> [HistorySample] {
        guard let url = fileURL, let data = try? Data(contentsOf: url),
              let samples = try? JSONDecoder().decode([HistorySample].self, from: data) else { return [] }
        return samples
    }

    /// Adds `sample` unless the newest point is less than `minimumGap` older, and drops points over a day old.
    public static func append(_ sample: HistorySample, minimumGap: TimeInterval) {
        guard let url = fileURL else { return }
        var samples = load()
        if let last = samples.last, sample.date.timeIntervalSince(last.date) < minimumGap { return }
        samples.append(sample)
        samples.sort { $0.date < $1.date }
        samples.removeAll { sample.date.timeIntervalSince($0.date) > window }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(samples).write(to: url, options: .atomic)
    }
}
