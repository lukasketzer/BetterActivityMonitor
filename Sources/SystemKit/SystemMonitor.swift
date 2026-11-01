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
    private let connections = ConnectionSampler()
    private let assertions = PowerAssertionSampler()
    private var lastSample: Date?
    private var tick = 0
    /// Wall-clock milliseconds each sampler took in the last `sample()`; used by the benchmark.
    public private(set) var lastTimings: [(name: String, ms: Double)] = []

    public init() {}

    /// Read every temperature sensor (costly) instead of a representative subset.
    public func setDetailedSensors(_ on: Bool) { sensors.detailed = on }

    /// Per-connection data costs a `nettop` run per tick, so it is only sampled while something shows it.
    public func setConnectionMode(_ mode: ConnectionMode) { connections.mode = mode }

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

        var procs = timed("processes") { processes.sample() }
        let temps = timed("sensors") { sensors.sample() }
        let net = timed("connections") { connections.sample(now: now) }
        if let net { Self.attach(net.processes, to: &procs) }
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
            processes: procs,
            connections: net,
            powerAssertions: timed("assertions") { assertions.sample(now: now) }
        )
        lastTimings = timings.map { (name: $0.0, ms: $0.1) }
        return snapshot
    }

    /// Copies nettop's per-process counters onto the matching process entries.
    static func attach(_ usage: [ProcessNetUsage], to processes: inout [ProcessEntry]) {
        guard !usage.isEmpty else { return }
        let byPID = Dictionary(usage.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        for i in processes.indices {
            guard let u = byPID[processes[i].pid] else { continue }
            processes[i].netRateIn = u.rateIn
            processes[i].netRateOut = u.rateOut
            processes[i].netTotalIn = u.bytesIn
            processes[i].netTotalOut = u.bytesOut
        }
    }
}
