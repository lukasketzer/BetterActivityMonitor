import Foundation
import SQLite3

/// One minute of the whole machine, averaged over the ticks the app sampled in it.
public struct SystemMinute: Sendable, Equatable {
    /// Start of the minute, seconds since 1970 (a multiple of 60).
    public var ts: Int
    public var cpu: Double            // 0...1
    public var cpuUser: Double
    public var cpuSystem: Double
    public var cpuMax: Double         // highest tick in the minute
    public var memUsed: Double        // 0...1
    public var memPressure: Int       // MemoryPressure raw value, worst in the minute
    public var swap: UInt64
    public var gpu: Double?
    public var netIn: Double          // bytes/s
    public var netOut: Double
    public var diskRead: Double
    public var diskWrite: Double
    public var cpuTempMax: Double?    // °C
    public var battery: Double?       // 0...1
    public var power: Double?         // W, whole Mac

    public init(ts: Int, cpu: Double, cpuUser: Double, cpuSystem: Double, cpuMax: Double, memUsed: Double,
                memPressure: Int, swap: UInt64, gpu: Double?, netIn: Double, netOut: Double, diskRead: Double,
                diskWrite: Double, cpuTempMax: Double?, battery: Double?, power: Double?) {
        self.ts = ts
        self.cpu = cpu
        self.cpuUser = cpuUser
        self.cpuSystem = cpuSystem
        self.cpuMax = cpuMax
        self.memUsed = memUsed
        self.memPressure = memPressure
        self.swap = swap
        self.gpu = gpu
        self.netIn = netIn
        self.netOut = netOut
        self.diskRead = diskRead
        self.diskWrite = diskWrite
        self.cpuTempMax = cpuTempMax
        self.battery = battery
        self.power = power
    }
}

/// One process in one minute. Only the top few per metric are kept.
public struct ProcessMinute: Sendable, Equatable {
    public var ts: Int
    public var pid: pid_t
    public var name: String
    /// App bundle path, so helpers can be summed under their app.
    public var bundle: String?
    public var cpu: Double            // % of one core, averaged
    public var memory: UInt64         // highest in the minute
    public var disk: Double           // bytes/s read + written
    public var net: Double?           // bytes/s in + out; nil when nettop had no baseline
    public var power: Double          // W

    public init(ts: Int, pid: pid_t, name: String, bundle: String?, cpu: Double, memory: UInt64, disk: Double,
                net: Double?, power: Double) {
        self.ts = ts
        self.pid = pid
        self.name = name
        self.bundle = bundle
        self.cpu = cpu
        self.memory = memory
        self.disk = disk
        self.net = net
        self.power = power
    }
}

public enum HistoryMetric: String, CaseIterable, Sendable {
    case cpu, cpuUser = "cpu_user", cpuSystem = "cpu_system", cpuMax = "cpu_max", memUsed = "mem_used"
    case memPressure = "mem_pressure", swap, gpu, netIn = "net_in", netOut = "net_out"
    case diskRead = "disk_read", diskWrite = "disk_write", cpuTempMax = "cpu_temp_max", battery, power

    /// Peaks stay peaks when minutes are merged into coarser buckets; everything else is averaged.
    var aggregate: String {
        switch self {
        case .cpuMax, .memPressure, .cpuTempMax: "MAX"
        default: "AVG"
        }
    }
}

public struct HistoryValue: Sendable, Hashable {
    public var date: Date
    public var value: Double
}

/// What one app or process used over a time range.
public struct ProcessSummary: Sendable, Hashable, Identifiable {
    public var id: String { key }
    /// Bundle path, or the process name outside any bundle.
    public var key: String
    public var name: String
    public var bundle: String?
    /// Most recent pid seen, to reveal it if it still runs.
    public var pid: pid_t
    /// Average % of one core over the minutes the app was recorded.
    public var cpu: Double
    public var memoryPeak: UInt64
    public var diskBytes: Double
    public var netBytes: Double
    /// Joules.
    public var energy: Double
    public var minutes: Int
}

public enum ProcessRanking: String, CaseIterable, Sendable {
    case cpu, memory, disk, net, energy

    var orderBy: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memory_peak"
        case .disk: "disk_bytes"
        case .net: "net_bytes"
        case .energy: "energy"
        }
    }
}

/// Minute-by-minute history on disk (SQLite from the SDK, no dependencies). The background agent
/// (`BAMHistoryAgent`) writes one row a minute; the app reads. WAL mode lets both use the file at once.
/// 30 days at 15 processes a minute is about 51 MB (see `HistoryDatabaseTests`).
public actor HistoryDatabase {
    private var db: OpaquePointer?
    public nonisolated let url: URL?

    public static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("BetterActivityMonitor/history.sqlite")
    }

    /// `url: nil` keeps the database in memory (tests).
    public init(url: URL? = HistoryDatabase.defaultURL) {
        self.url = url
        if let url {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url?.path ?? ":memory:", &handle,
                              SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            return
        }
        db = handle
        // The agent writes while the app reads or clears; wait for the other's lock instead of failing.
        sqlite3_busy_timeout(handle, 3000)
        // auto_vacuum only takes effect before the first table exists.
        for sql in [
            "PRAGMA auto_vacuum = INCREMENTAL",
            "PRAGMA journal_mode = WAL",
            "PRAGMA synchronous = NORMAL",
            """
            CREATE TABLE IF NOT EXISTS system(
                ts INTEGER PRIMARY KEY, cpu REAL, cpu_user REAL, cpu_system REAL, cpu_max REAL,
                mem_used REAL, mem_pressure INTEGER, swap INTEGER, gpu REAL, net_in REAL, net_out REAL,
                disk_read REAL, disk_write REAL, cpu_temp_max REAL, battery REAL, power REAL)
            """,
            """
            CREATE TABLE IF NOT EXISTS process(
                ts INTEGER NOT NULL, pid INTEGER NOT NULL, name TEXT NOT NULL, bundle TEXT,
                cpu REAL, memory INTEGER, disk REAL, net REAL, power REAL)
            """,
            "CREATE INDEX IF NOT EXISTS process_ts ON process(ts)",
        ] { Self.exec(handle, sql) }
    }

    deinit { sqlite3_close(db) }

    public var isOpen: Bool { db != nil }

    // MARK: Writing

    public func append(_ minute: SystemMinute, processes: [ProcessMinute]) {
        guard let db else { return }
        Self.exec(db, "BEGIN")
        defer { Self.exec(db, "COMMIT") }
        let system = Statement(db, """
            INSERT OR REPLACE INTO system VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """)
        system.bind(minute.ts, minute.cpu, minute.cpuUser, minute.cpuSystem, minute.cpuMax, minute.memUsed,
                    minute.memPressure, Int(clamping: minute.swap), minute.gpu, minute.netIn, minute.netOut,
                    minute.diskRead, minute.diskWrite, minute.cpuTempMax, minute.battery, minute.power)
        system.run()

        Self.exec(db, "DELETE FROM process WHERE ts = \(minute.ts)")
        let process = Statement(db, "INSERT INTO process VALUES (?,?,?,?,?,?,?,?,?)")
        for p in processes {
            process.reset()
            process.bind(p.ts, Int(p.pid), p.name, p.bundle, p.cpu, Int(clamping: p.memory), p.disk, p.net, p.power)
            process.run()
        }
    }

    /// Drops minutes before `date` and returns the freed pages to the file system.
    public func prune(olderThan date: Date) {
        guard let db else { return }
        let cutoff = Int(date.timeIntervalSince1970)
        Self.exec(db, "DELETE FROM system WHERE ts < \(cutoff)")
        Self.exec(db, "DELETE FROM process WHERE ts < \(cutoff)")
        Self.exec(db, "PRAGMA incremental_vacuum")
    }

    public func clear() {
        guard let db else { return }
        Self.exec(db, "DELETE FROM system")
        Self.exec(db, "DELETE FROM process")
        Self.exec(db, "PRAGMA incremental_vacuum")
    }

    // MARK: Reading

    /// Bytes the database uses (pages in use, without the WAL).
    public func size() -> Int {
        guard let db else { return 0 }
        func pragma(_ name: String) -> Int {
            let s = Statement(db, "PRAGMA \(name)")
            return s.step() ? s.int(0) : 0
        }
        return (pragma("page_count") - pragma("freelist_count")) * pragma("page_size")
    }

    public func minuteCount() -> Int {
        guard let db else { return 0 }
        let s = Statement(db, "SELECT COUNT(*) FROM system")
        return s.step() ? s.int(0) : 0
    }

    /// Values of `metric` between `start` and `end`, merged into buckets of `bucket` seconds
    /// (a multiple of 60; 60 returns the raw minutes). Buckets with no data are left out.
    public func series(_ metric: HistoryMetric, from start: Date, to end: Date, bucket: Int = 60) -> [HistoryValue] {
        guard let db else { return [] }
        let size = max(bucket / 60 * 60, 60)
        let s = Statement(db, """
            SELECT (ts / \(size)) * \(size) AS b, \(metric.aggregate)(\(metric.rawValue)) FROM system
            WHERE ts >= ? AND ts < ? AND \(metric.rawValue) IS NOT NULL GROUP BY b ORDER BY b
            """)
        s.bind(Int(start.timeIntervalSince1970), Int(end.timeIntervalSince1970))
        var result: [HistoryValue] = []
        while s.step() {
            result.append(HistoryValue(date: Date(timeIntervalSince1970: TimeInterval(s.int(0))), value: s.double(1)))
        }
        return result
    }

    /// The processes recorded in the minute containing `date`.
    public func processes(at date: Date) -> [ProcessMinute] {
        guard let db else { return [] }
        let ts = Int(date.timeIntervalSince1970) / 60 * 60
        let s = Statement(db, "SELECT ts, pid, name, bundle, cpu, memory, disk, net, power FROM process WHERE ts = ? ORDER BY cpu DESC")
        s.bind(ts)
        var result: [ProcessMinute] = []
        while s.step() {
            result.append(ProcessMinute(ts: s.int(0), pid: pid_t(s.int(1)), name: s.text(2) ?? "", bundle: s.text(3),
                                        cpu: s.double(4), memory: UInt64(max(s.int(5), 0)), disk: s.double(6),
                                        net: s.isNull(7) ? nil : s.double(7), power: s.double(8)))
        }
        return result
    }

    /// Apps (helpers summed under their bundle) ranked by what they used between `start` and `end`.
    /// CPU averages over every recorded minute in the range, so an app that only ran briefly ranks low.
    public func topProcesses(from start: Date, to end: Date, by ranking: ProcessRanking, limit: Int = 15) -> [ProcessSummary] {
        guard let db else { return [] }
        let range = [Int(start.timeIntervalSince1970), Int(end.timeIntervalSince1970)]
        let minutes: Int = {
            let s = Statement(db, "SELECT COUNT(*) FROM system WHERE ts >= ? AND ts < ?")
            s.bind(range[0], range[1])
            return max(s.step() ? s.int(0) : 0, 1)
        }()
        // Per minute first (helpers of one app add up), then over the range. The pid column picks the
        // newest minute's pid (macOS pids stay below 100 000).
        let s = Statement(db, """
            WITH per_minute AS (
                SELECT ts, COALESCE(bundle, name) AS key, MAX(name) AS name, bundle, MAX(pid) AS pid,
                       SUM(cpu) AS cpu, SUM(memory) AS memory, SUM(disk) AS disk, SUM(net) AS net, SUM(power) AS power
                FROM process WHERE ts >= ? AND ts < ? GROUP BY ts, key)
            SELECT key, name, bundle, MAX(ts * 1000000 + pid) % 1000000,
                   SUM(cpu) / \(minutes) AS cpu, MAX(memory) AS memory_peak, SUM(disk) * 60 AS disk_bytes,
                   SUM(COALESCE(net, 0)) * 60 AS net_bytes, SUM(power) * 60 AS energy, COUNT(*) AS minutes
            FROM per_minute GROUP BY key ORDER BY \(ranking.orderBy) DESC LIMIT ?
            """)
        s.bind(range[0], range[1], limit)
        var result: [ProcessSummary] = []
        while s.step() {
            let bundle = s.text(2)
            result.append(ProcessSummary(
                key: s.text(0) ?? "", name: bundle.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension } ?? s.text(1) ?? "",
                bundle: bundle, pid: pid_t(s.int(3)), cpu: s.double(4), memoryPeak: UInt64(max(s.int(5), 0)),
                diskBytes: s.double(6), netBytes: s.double(7), energy: s.double(8), minutes: s.int(9)))
        }
        return result
    }

    // MARK: SQLite plumbing

    private static func exec(_ db: OpaquePointer?, _ sql: String) {
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    /// A prepared statement; finalized when released.
    private final class Statement {
        private var handle: OpaquePointer?

        init(_ db: OpaquePointer, _ sql: String) {
            sqlite3_prepare_v2(db, sql, -1, &handle, nil)
        }

        deinit { sqlite3_finalize(handle) }

        func reset() {
            sqlite3_reset(handle)
            sqlite3_clear_bindings(handle)
        }

        func bind(_ values: Any?...) {
            // SQLITE_TRANSIENT: SQLite copies the text, so Swift strings needn't outlive the call.
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            for (i, value) in values.enumerated() {
                let index = Int32(i + 1)
                switch value {
                case let v as Int: sqlite3_bind_int64(handle, index, Int64(v))
                case let v as Double: sqlite3_bind_double(handle, index, v)
                case let v as String: sqlite3_bind_text(handle, index, v, -1, transient)
                default: sqlite3_bind_null(handle, index)
                }
            }
        }

        @discardableResult
        func run() -> Bool { sqlite3_step(handle) == SQLITE_DONE }

        func step() -> Bool { sqlite3_step(handle) == SQLITE_ROW }

        func int(_ column: Int32) -> Int { Int(sqlite3_column_int64(handle, column)) }
        func double(_ column: Int32) -> Double { sqlite3_column_double(handle, column) }
        func isNull(_ column: Int32) -> Bool { sqlite3_column_type(handle, column) == SQLITE_NULL }
        func text(_ column: Int32) -> String? {
            guard let c = sqlite3_column_text(handle, column) else { return nil }
            return String(cString: c)
        }
    }
}
