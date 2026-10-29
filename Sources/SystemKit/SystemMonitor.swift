import Foundation

/// Owns all samplers; each call to `sample()` produces a snapshot with rates relative to the previous call.
public actor SystemMonitor {
    private let cpu = CPUSampler()
    private let memory = MemorySampler()
    private let processes = ProcessSampler()
    private let network = NetworkSampler()
    private let disks = DiskSampler()
    private let gpu = GPUSampler()
    private let battery = BatterySampler()
    private let sensors = TemperatureSampler()
    private var lastSample: Date?
    private var tick = 0
    /// Wall-clock milliseconds each sampler took in the last `sample()`; used by the benchmark.
    public private(set) var lastTimings: [(name: String, ms: Double)] = []

    public init() {}

    /// Read every temperature sensor (costly) instead of a representative subset.
    public func setDetailedSensors(_ on: Bool) { sensors.detailed = on }

    public func sample() -> SystemSnapshot {
        let now = Date()
        let interval = lastSample.map { now.timeIntervalSince($0) } ?? 0
        lastSample = now
        tick += 1

        var timings: [(String, Double)] = []
        func timed<T>(_ name: String, _ body: () -> T) -> T {
            let start = DispatchTime.now().uptimeNanoseconds
            let value = body()
            timings.append((name, Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6))
            return value
        }

        let procs = timed("processes") { processes.sample() }
        let temps = timed("sensors") { sensors.sample() }
        let snapshot = SystemSnapshot(
            timestamp: now,
            interval: interval,
            cpu: timed("cpu") { cpu.sample(processCount: procs.count, threadCount: processes.totalThreads) },
            memory: timed("memory") { memory.sample() },
            network: timed("network") { network.sample() },
            disks: timed("disks") { disks.sample() },
            gpu: timed("gpu") { gpu.sample() },
            battery: timed("battery") { battery.sample() },
            sensors: temps.sensors,
            fans: temps.fans,
            processes: procs
        )
        lastTimings = timings.map { (name: $0.0, ms: $0.1) }
        return snapshot
    }
}
