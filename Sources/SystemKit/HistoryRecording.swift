import Foundation

public enum AppBundle {
    /// The outermost `.app` bundle an executable lives in, so helpers nested in
    /// `Foo.app/Contents/Frameworks/…/Helper.app` count as `Foo.app`.
    public static func path(forExecutable path: String) -> String? {
        guard let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }

    public static func name(ofBundle path: String) -> String {
        ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }
}

/// Settings the app writes and the background agent reads, in the app's defaults domain.
public enum HistorySettings {
    public static let appDomain = "dev.lukas.BetterActivityMonitor"
    public static let enabledKey = "history.enabled"
    public static let retentionKey = "history.retentionDays"
    public static let retentionChoices = [1, 7, 30]
    public static let defaultRetention = 7

    /// The app's defaults. The agent lives inside the app bundle, where Foundation may already treat the
    /// app as the main bundle, and a suite named after the main bundle isn't supported.
    public static var appDefaults: UserDefaults {
        Bundle.main.bundleIdentifier == appDomain ? .standard : UserDefaults(suiteName: appDomain) ?? .standard
    }

    /// Days of minute history to keep: 1, 7 or 30.
    public static func retentionDays(_ defaults: UserDefaults?) -> Int {
        let days = defaults?.integer(forKey: retentionKey) ?? 0
        return retentionChoices.contains(days) ? days : defaultRetention
    }
}

extension SystemSnapshot {
    /// What the whole Mac draws: battery telemetry when there is one, else the sum over processes
    /// (desktops have no battery telemetry).
    public var systemPower: Double {
        if let load = battery?.systemLoad, load > 0 { return load }
        if let w = battery?.watts, !(battery?.isPluggedIn ?? true) { return abs(w) }
        return processes.reduce(0) { $0 + $1.power }
    }
}

/// Everything sampled in one wall-clock minute, folded into averages and peaks.
public struct MinuteBucket {
    struct ProcessTotals {
        var name: String
        var bundle: String?
        var cpu = 0.0
        var memoryPeak: UInt64 = 0
        var disk = 0.0
        var power = 0.0
    }

    public let ts: Int
    public private(set) var ticks = 0
    private var cpu = 0.0, cpuUser = 0.0, cpuSystem = 0.0, cpuMax = 0.0
    private var memUsed = 0.0, pressure = 0, swap: UInt64 = 0
    private var gpu = 0.0, gpuTicks = 0
    private var netIn = 0.0, netOut = 0.0, diskRead = 0.0, diskWrite = 0.0
    private var tempMax: Double?
    private var battery: Double?
    private var power = 0.0
    var processes: [pid_t: ProcessTotals] = [:]

    public init(ts: Int) { self.ts = ts }

    public static func minute(of date: Date) -> Int { Int(date.timeIntervalSince1970) / 60 * 60 }

    /// Name history shows for a process: its app for anything inside a bundle, else the process name.
    public static func name(of p: ProcessEntry) -> String {
        AppBundle.path(forExecutable: p.path).map(AppBundle.name(ofBundle:)) ?? p.name
    }

    public mutating func add(_ s: SystemSnapshot, name: (ProcessEntry) -> String = MinuteBucket.name(of:)) {
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
        power += s.systemPower
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
    public func finish(net: [pid_t: Double]?, top: Int = 5) -> (SystemMinute, [ProcessMinute]) {
        let n = Double(max(ticks, 1))
        let minute = SystemMinute(
            ts: ts, cpu: cpu / n, cpuUser: cpuUser / n, cpuSystem: cpuSystem / n, cpuMax: cpuMax,
            memUsed: memUsed / n, memPressure: pressure, swap: swap,
            gpu: gpuTicks > 0 ? gpu / Double(gpuTicks) : nil,
            netIn: netIn / n, netOut: netOut / n, diskRead: diskRead / n, diskWrite: diskWrite / n,
            cpuTempMax: tempMax, battery: battery, power: power / n)

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
public struct NetReading {
    public var date: Date
    public var totals: [pid_t: UInt64]

    public init(date: Date, usage: [ProcessNetUsage]) {
        self.date = date
        totals = Dictionary(usage.map { ($0.pid, $0.bytesIn + $0.bytesOut) }, uniquingKeysWith: max)
    }

    /// Bytes per second between two readings, for processes present in both. A process that exited
    /// in between loses its last bytes; one that started has no baseline yet.
    public func rates(since earlier: NetReading) -> [pid_t: Double] {
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

/// What the background agent does: sample every `interval` seconds, fold samples into minutes,
/// write each finished minute, prune old ones. One cheap `nettop -P` run per minute adds per-process
/// network bytes.
public actor HistoryRecorder {
    public let database: HistoryDatabase
    public let interval: TimeInterval
    private let retentionDays: @Sendable () -> Int
    private let monitor: SystemMonitor
    private var bucket: MinuteBucket?
    private var previousNet: NetReading?
    private var latestNet: NetReading?
    private var lastPrune: Date?
    private var lastSample: Date?

    public init(database: HistoryDatabase, interval: TimeInterval = 15, monitor: SystemMonitor = SystemMonitor(),
                retentionDays: @escaping @Sendable () -> Int) {
        self.database = database
        self.interval = interval
        self.monitor = monitor
        self.retentionDays = retentionDays
    }

    /// Runs until the task is cancelled, sampling on multiples of `interval` past the minute.
    public func run() async {
        while !Task.isCancelled {
            await tick()
            let now = Date().timeIntervalSince1970
            let next = (now / interval).rounded(.down) * interval + interval
            try? await Task.sleep(for: .seconds(max(next - now, 0.5)))
        }
    }

    /// One sample. The last tick of each minute also reads nettop.
    public func tick(now: Date = Date()) async {
        let ts = MinuteBucket.minute(of: now)
        let secondsIn = now.timeIntervalSince1970 - Double(ts)
        let needsNet = secondsIn >= 60 - interval && latestNet.map { MinuteBucket.minute(of: $0.date) != ts } ?? true
        if needsNet { await monitor.setConnectionMode(.processes) }
        let snapshot = await monitor.sample()
        if needsNet { await monitor.setConnectionMode(.off) }
        await record(snapshot, now: now)
    }

    /// Folds one snapshot in; exposed for tests, which feed snapshots directly.
    public func record(_ s: SystemSnapshot, now: Date) async {
        let ts = MinuteBucket.minute(of: now)
        if let finished = bucket, finished.ts != ts {
            await finish(finished)
            bucket = nil
        }
        // Rates need a recent previous sample: the first one has none, and after sleep the previous one
        // is hours old, so its rates would smear the whole night into one minute.
        let fresh = lastSample.map { now.timeIntervalSince($0) <= interval * 4 } ?? false
        lastSample = now
        if let connections = s.connections { latestNet = NetReading(date: now, usage: connections.processes) }
        guard fresh else { return }
        if bucket == nil { bucket = MinuteBucket(ts: ts) }
        bucket?.add(s)
    }

    private func finish(_ bucket: MinuteBucket) async {
        var net: [pid_t: Double]?
        if let latestNet, MinuteBucket.minute(of: latestNet.date) == bucket.ts {
            if let previousNet, latestNet.date.timeIntervalSince(previousNet.date) <= 120 {
                net = latestNet.rates(since: previousNet)
            }
            previousNet = latestNet
        }
        let (minute, processes) = bucket.finish(net: net)
        await database.append(minute, processes: processes)
        let now = Date()
        if lastPrune.map({ now.timeIntervalSince($0) >= 3600 }) ?? true {
            lastPrune = now
            await database.prune(olderThan: now.addingTimeInterval(-Double(retentionDays()) * 86_400))
        }
    }
}
