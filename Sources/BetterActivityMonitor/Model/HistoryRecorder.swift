import Foundation
import SystemKit

/// Everything sampled in one wall-clock minute, folded into averages and peaks.
struct MinuteBucket {
    struct ProcessTotals {
        var name: String
        var bundle: String?
        var cpu = 0.0
        var memoryPeak: UInt64 = 0
        var disk = 0.0
        var power = 0.0
    }

    let ts: Int
    private(set) var ticks = 0
    private var cpu = 0.0, cpuUser = 0.0, cpuSystem = 0.0, cpuMax = 0.0
    private var memUsed = 0.0, pressure = 0, swap: UInt64 = 0
    private var gpu = 0.0, gpuTicks = 0
    private var netIn = 0.0, netOut = 0.0, diskRead = 0.0, diskWrite = 0.0
    private var tempMax: Double?
    private var battery: Double?
    private var power = 0.0, powerTicks = 0
    private(set) var processes: [pid_t: ProcessTotals] = [:]

    init(ts: Int) { self.ts = ts }

    static func minute(of date: Date) -> Int { Int(date.timeIntervalSince1970) / 60 * 60 }

    mutating func add(_ s: SystemSnapshot, systemPower: Double?, name: (ProcessEntry) -> String) {
        ticks += 1
        cpu += s.cpu.total
        cpuUser += s.cpu.user
        cpuSystem += s.cpu.system
        cpuMax = max(cpuMax, s.cpu.total)
        memUsed += s.memory.usedFraction
        pressure = max(pressure, s.memory.pressure.rawValue)
        swap = max(swap, s.memory.swapUsed)
        if let g = s.gpu {
            gpu += g.utilization
            gpuTicks += 1
        }
        netIn += s.network.rateIn
        netOut += s.network.rateOut
        diskRead += s.disks.readRate
        diskWrite += s.disks.writeRate
        if let hottest = s.sensors.filter({ $0.category == .cpu }).map(\.celsius).max() {
            tempMax = max(tempMax ?? hottest, hottest)
        }
        if let b = s.battery { battery = b.charge }
        if let systemPower {
            power += systemPower
            powerTicks += 1
        }
        for p in s.processes where p.hasTaskInfo {
            var totals = processes[p.pid]
                ?? ProcessTotals(name: name(p), bundle: AppBundle.path(forExecutable: p.path))
            totals.cpu += p.cpu
            totals.memoryPeak = max(totals.memoryPeak, p.memory)
            totals.disk += p.diskReadRate + p.diskWriteRate
            totals.power += p.power
            processes[p.pid] = totals
        }
    }

    /// The finished minute, plus the union of the top `top` processes by each metric.
    /// `net` holds per-process network rates (bytes/s) when nettop gave two readings to diff.
    func finish(net: [pid_t: Double]?, top: Int = 5) -> (SystemMinute, [ProcessMinute]) {
        let n = Double(max(ticks, 1))
        let minute = SystemMinute(
            ts: ts, cpu: cpu / n, cpuUser: cpuUser / n, cpuSystem: cpuSystem / n, cpuMax: cpuMax,
            memUsed: memUsed / n, memPressure: pressure, swap: swap,
            gpu: gpuTicks > 0 ? gpu / Double(gpuTicks) : nil,
            netIn: netIn / n, netOut: netOut / n, diskRead: diskRead / n, diskWrite: diskWrite / n,
            cpuTempMax: tempMax, battery: battery, power: powerTicks > 0 ? power / Double(powerTicks) : nil)

        // A process seen in only some ticks is averaged over the whole minute, like the system values.
        let rows = processes.map { pid, t in
            ProcessMinute(ts: ts, pid: pid, name: t.name, bundle: t.bundle, cpu: t.cpu / n, memory: t.memoryPeak,
                          disk: t.disk / n, net: net?[pid], power: t.power / n)
        }
        var keep = Set<pid_t>()
        let rankings: [(ProcessMinute) -> Double] = [
            { $0.cpu }, { Double($0.memory) }, { $0.disk }, { $0.net ?? 0 }, { $0.power },
        ]
        for value in rankings {
            for row in rows.filter({ value($0) > 0 }).sorted(by: { value($0) > value($1) }).prefix(top) {
                keep.insert(row.pid)
            }
        }
        return (minute, rows.filter { keep.contains($0.pid) }.sorted { $0.pid < $1.pid })
    }
}

/// nettop's per-process byte counters at one moment.
struct NetReading {
    var date: Date
    var totals: [pid_t: UInt64]

    init(date: Date, usage: [ProcessNetUsage]) {
        self.date = date
        totals = Dictionary(usage.map { ($0.pid, $0.bytesIn + $0.bytesOut) }, uniquingKeysWith: max)
    }

    /// Bytes per second between two readings, for processes present in both. A process that exited
    /// in between loses its last bytes; one that started has no baseline yet.
    func rates(since earlier: NetReading) -> [pid_t: Double] {
        let dt = date.timeIntervalSince(earlier.date)
        guard dt > 0 else { return [:] }
        var result: [pid_t: Double] = [:]
        for (pid, total) in totals {
            guard let before = earlier.totals[pid], total >= before else { continue }
            result[pid] = Double(total - before) / dt
        }
        return result
    }
}

/// Folds every tick into minutes and writes each finished minute to `HistoryStore`, off the main thread.
@MainActor
final class HistoryRecorder {
    let store: HistoryStore
    /// Called with each finished minute, whether or not history is being saved (the widgets use it).
    var onMinute: ((SystemMinute) -> Void)?

    private var bucket: MinuteBucket?
    private var previousNet: NetReading?
    private var latestNet: NetReading?
    private var lastPrune: Date?

    init(store: HistoryStore = HistoryStore()) {
        self.store = store
    }

    /// Records one tick; returns the connection mode the recorder needs right now. It asks for one
    /// cheap `nettop -P` reading near the end of each minute, unless something else already runs nettop.
    func record(_ s: SystemSnapshot, systemPower: Double?, name: (ProcessEntry) -> String) -> ConnectionMode {
        let ts = MinuteBucket.minute(of: s.timestamp)
        if let finished = bucket, finished.ts != ts {
            finish(finished)
            bucket = nil
        }
        if bucket == nil { bucket = MinuteBucket(ts: ts) }
        bucket?.add(s, systemPower: systemPower, name: name)

        if let connections = s.connections {
            latestNet = NetReading(date: s.timestamp, usage: connections.processes)
        }
        let secondsIn = s.timestamp.timeIntervalSince1970 - Double(ts)
        let haveReading = latestNet.map { MinuteBucket.minute(of: $0.date) == ts } ?? false
        return Defaults.historyEnabled && secondsIn >= 50 && !haveReading ? .processes : .off
    }

    private func finish(_ bucket: MinuteBucket) {
        var net: [pid_t: Double]?
        if let latestNet, MinuteBucket.minute(of: latestNet.date) == bucket.ts {
            if let previousNet { net = latestNet.rates(since: previousNet) }
            previousNet = latestNet
        }
        let (minute, processes) = bucket.finish(net: net)
        onMinute?(minute)
        guard Defaults.historyEnabled else { return }
        let store = store
        let now = Date()
        let prune = lastPrune.map { now.timeIntervalSince($0) >= 3600 } ?? true
        if prune { lastPrune = now }
        let cutoff = now.addingTimeInterval(-Double(Defaults.historyRetentionDays) * 86_400)
        Task.detached(priority: .utility) {
            await store.append(minute, processes: processes)
            if prune { await store.prune(olderThan: cutoff) }
        }
    }
}
