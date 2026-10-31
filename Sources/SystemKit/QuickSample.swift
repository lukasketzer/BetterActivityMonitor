import Foundation

/// One-off readings for short-lived callers like the widget extension, which can't keep a
/// `SystemMonitor` running. Only uses APIs that work inside the app sandbox (no SMC, no other processes).
public enum QuickSample {
    public static func memory() -> MemoryStats { MemorySampler().sample() }

    /// CPU load over `interval`; blocks the caller for that long.
    public static func cpu(over interval: TimeInterval = 0.5) -> CPUStats {
        let sampler = CPUSampler()
        _ = sampler.sample(processCount: 0, threadCount: 0)
        Thread.sleep(forTimeInterval: interval)
        return sampler.sample(processCount: 0, threadCount: 0)
    }

    public static func volumes() -> [Volume] { DiskSampler.readVolumes() }

    /// GPU utilization 0...1, or nil when no GPU reports statistics.
    public static func gpu() -> Double? { GPUSampler().sample()?.utilization }

    public static func battery() -> BatteryStats? { BatterySampler().sample() }

    public static var bootDate: Date {
        let boot = Sysctl.value("kern.boottime", as: timeval.self, initial: timeval())
        return boot.map { Date(timeIntervalSince1970: TimeInterval($0.tv_sec)) } ?? Date()
    }
}
