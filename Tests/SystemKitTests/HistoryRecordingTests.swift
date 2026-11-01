import Foundation
import XCTest
@testable import SystemKit

final class MinuteBucketTests: XCTestCase {
    static func snapshot(at date: Date, cpu: Double, memory: Double = 0.5, pressure: MemoryPressure = .normal,
                         temp: Double? = nil, interval: TimeInterval = 15, processes: [ProcessEntry] = [],
                         connections: ConnectionStats? = nil) -> SystemSnapshot {
        SystemSnapshot(
            timestamp: date, interval: interval,
            cpu: CPUStats(user: cpu / 2, system: cpu / 2, cores: [], coreKinds: [], loadAverage: [0, 0, 0], uptime: 0,
                          model: "", physicalCores: 1, logicalCores: 1, performanceCores: 1, efficiencyCores: 0,
                          processCount: processes.count, threadCount: 1),
            memory: MemoryStats(total: 100, app: UInt64(memory * 100), wired: 0, compressed: 0, cached: 0, free: 0,
                                swapTotal: 0, swapUsed: 0, pressure: pressure, pageIns: 0, pageOuts: 0,
                                pageInsPerSecond: 0, pageOutsPerSecond: 0, compressionsPerSecond: 0),
            network: NetworkStats(interfaces: [], rateIn: 100, rateOut: 10, totalIn: 0, totalOut: 0),
            disks: DiskStats(devices: [], volumes: [], readRate: 0, writeRate: 0, totalRead: 0, totalWritten: 0),
            gpu: nil, battery: nil,
            sensors: temp.map { [SensorReading(name: "die", celsius: $0, category: .cpu)] } ?? [],
            fans: [], processes: processes, connections: connections)
    }

    static func process(_ pid: pid_t, cpu: Double = 0, memory: UInt64 = 0, power: Double = 0, path: String = "/bin/p",
                        taskInfo: Bool = true) -> ProcessEntry {
        var e = ProcessEntry(pid: pid, ppid: 1, uid: 501, user: "me", name: "p\(pid)", path: path, state: .running,
                             nice: 0, startTime: .distantPast, hasTaskInfo: taskInfo, cpu: cpu, cpuTime: 0, memory: memory,
                             resident: 0, threads: 1, diskReadRate: 0, diskWriteRate: 0, diskReadTotal: 0,
                             diskWriteTotal: 0, idleWakeupsPerSecond: 0)
        e.power = power
        return e
    }

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000 / 60 * 60)

    func testAveragesPeaksAndWorstPressure() {
        var bucket = MinuteBucket(ts: MinuteBucket.minute(of: t0))
        bucket.add(Self.snapshot(at: t0, cpu: 0.2, temp: 50, processes: [Self.process(1, power: 4)]))
        bucket.add(Self.snapshot(at: t0 + 15, cpu: 0.6, pressure: .warning, temp: 70))
        let (minute, _) = bucket.finish(net: nil)
        XCTAssertEqual(minute.cpu, 0.4, accuracy: 1e-9)
        XCTAssertEqual(minute.cpuMax, 0.6, accuracy: 1e-9)
        XCTAssertEqual(minute.cpuTempMax, 70)
        XCTAssertEqual(minute.memPressure, MemoryPressure.warning.rawValue)
        XCTAssertEqual(minute.power ?? 0, 2, accuracy: 1e-9, "no battery: the processes' sum, averaged")
        XCTAssertNil(minute.gpu)
        XCTAssertEqual(minute.netIn, 100)
    }

    func testKeepsTheUnionOfTopProcessesPerMetric() {
        var bucket = MinuteBucket(ts: MinuteBucket.minute(of: t0))
        var processes = (1...10).map { Self.process(pid_t($0), cpu: Double($0)) }
        processes.append(Self.process(50, memory: 1 << 30))
        processes.append(Self.process(60, power: 9))
        processes.append(Self.process(70, cpu: 99, taskInfo: false))
        bucket.add(Self.snapshot(at: t0, cpu: 0.5, processes: processes))
        bucket.add(Self.snapshot(at: t0 + 15, cpu: 0.5, processes: Array(processes.prefix(1))))
        let (_, kept) = bucket.finish(net: [3: 500], top: 3)
        XCTAssertEqual(Set(kept.map(\.pid)), [10, 9, 8, 50, 60, 3], "top 3 CPU + memory + power + network")
        XCTAssertEqual(kept.first { $0.pid == 10 }?.cpu ?? 0, 5, accuracy: 1e-9, "seen in one of two ticks")
        XCTAssertEqual(kept.first { $0.pid == 3 }?.net, 500)
    }

    func testAppsAreNamedAfterTheirBundle() {
        var bucket = MinuteBucket(ts: 0)
        bucket.add(Self.snapshot(at: t0, cpu: 0, processes: [
            Self.process(1, cpu: 1, path: "/Applications/Visual Studio Code.app/Contents/MacOS/Code"),
            Self.process(2, cpu: 1, path: "/usr/sbin/syslogd"),
        ]))
        let rows = bucket.finish(net: nil).1
        XCTAssertEqual(rows.first { $0.pid == 1 }?.name, "Visual Studio Code")
        XCTAssertEqual(rows.first { $0.pid == 1 }?.bundle, "/Applications/Visual Studio Code.app")
        XCTAssertEqual(rows.first { $0.pid == 2 }?.name, "p2")
    }

    func testNetRatesNeedTwoReadings() {
        let usage = { (pid: pid_t, bytes: UInt64) in ProcessNetUsage(pid: pid, name: "x", bytesIn: bytes, bytesOut: 0, rateIn: 0, rateOut: 0) }
        let before = NetReading(date: t0, usage: [usage(1, 100), usage(2, 10)])
        let after = NetReading(date: t0 + 60, usage: [usage(1, 1300), usage(3, 18)])
        let rates = after.rates(since: before)
        XCTAssertEqual(rates[1], 20, "1200 bytes over 60 s")
        XCTAssertNil(rates[2], "exited")
        XCTAssertNil(rates[3], "no baseline")
    }
}

final class HistoryRecorderTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000 / 60 * 60)

    func testWritesEachFinishedMinuteAndSkipsTheFirstSampleAndSleep() async {
        let db = HistoryDatabase(url: nil)
        let recorder = HistoryRecorder(database: db) { 7 }
        let snap = { (offset: TimeInterval, cpu: Double) in MinuteBucketTests.snapshot(at: self.t0 + offset, cpu: cpu) }
        await recorder.record(snap(0, 0.9), now: t0)          // first sample: no rates yet, ignored
        for s in stride(from: 15.0, through: 45, by: 15) { await recorder.record(snap(s, 0.2), now: t0 + s) }
        await recorder.record(snap(60, 0.4), now: t0 + 60)     // next minute: the first one is written
        var minutes = await db.series(.cpu, from: t0, to: t0 + 3600)
        XCTAssertEqual(minutes.count, 1)
        XCTAssertEqual(minutes.first?.value ?? 0, 0.2, accuracy: 1e-9, "the primer's 90 % is not part of it")

        // The Mac slept for an hour: the first sample after waking only re-primes.
        await recorder.record(snap(3700, 0.9), now: t0 + 3700)
        await recorder.record(snap(3715, 0.1), now: t0 + 3715)
        await recorder.record(snap(3780, 0.1), now: t0 + 3780)
        minutes = await db.series(.cpu, from: t0, to: t0 + 7200)
        XCTAssertEqual(minutes.count, 3)
        XCTAssertEqual(minutes[1].value, 0.4, accuracy: 1e-9, "minute 1 had one sample before sleep")
        XCTAssertEqual(minutes[2].value, 0.1, accuracy: 1e-9, "the wake-up sample is left out")
    }

    func testPerProcessNetworkComesFromConsecutiveMinutes() async {
        let db = HistoryDatabase(url: nil)
        let recorder = HistoryRecorder(database: db) { 7 }
        func net(_ bytes: UInt64) -> ConnectionStats {
            ConnectionStats(mode: .processes, flows: [],
                            processes: [ProcessNetUsage(pid: 5, name: "x", bytesIn: bytes, bytesOut: 0, rateIn: 0, rateOut: 0)])
        }
        let p = [MinuteBucketTests.process(5, cpu: 10)]
        let base = t0
        await recorder.record(MinuteBucketTests.snapshot(at: base, cpu: 0, processes: p), now: base)
        await recorder.record(MinuteBucketTests.snapshot(at: base + 45, cpu: 0, processes: p, connections: net(1000)), now: base + 15)
        await recorder.record(MinuteBucketTests.snapshot(at: base + 45, cpu: 0, processes: p, connections: net(1000)), now: base + 45)
        await recorder.record(MinuteBucketTests.snapshot(at: base + 105, cpu: 0, processes: p, connections: net(7000)), now: base + 60)
        await recorder.record(MinuteBucketTests.snapshot(at: base + 105, cpu: 0, processes: p, connections: net(7000)), now: base + 105)
        await recorder.record(MinuteBucketTests.snapshot(at: base + 120, cpu: 0, processes: p), now: base + 120)
        let first = await db.processes(at: base)
        let second = await db.processes(at: base + 60)
        XCTAssertNil(first.first?.net, "no earlier reading to diff against")
        XCTAssertEqual(second.first?.net ?? 0, 100, accuracy: 1e-9, "6000 bytes over 60 s")
    }

    /// The real samplers end to end: one tick primes, the next writes nothing until the minute turns.
    func testRealTickSamples() async {
        let db = HistoryDatabase(url: nil)
        let recorder = HistoryRecorder(database: db) { 7 }
        let start = t0
        await recorder.tick(now: start + 50)
        await recorder.tick(now: start + 55)
        await recorder.tick(now: start + 61)
        let minutes = await db.series(.cpu, from: start, to: start + 120)
        XCTAssertEqual(minutes.count, 1)
        XCTAssertGreaterThan(minutes.first?.value ?? -1, 0)
    }
}
