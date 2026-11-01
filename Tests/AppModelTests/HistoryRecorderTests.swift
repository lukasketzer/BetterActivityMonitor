import Foundation
import SwiftUI
import XCTest
@testable import BetterActivityMonitor
@testable import SystemKit

final class MinuteBucketTests: XCTestCase {
    static func snapshot(at date: Date, cpu: Double, memory: Double = 0.5, pressure: MemoryPressure = .normal,
                         temp: Double? = nil, processes: [ProcessEntry] = []) -> SystemSnapshot {
        SystemSnapshot(
            timestamp: date, interval: 1,
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
            fans: [], processes: processes, connections: nil)
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
        bucket.add(Self.snapshot(at: t0, cpu: 0.2, temp: 50), systemPower: 4, name: \.name)
        bucket.add(Self.snapshot(at: t0 + 1, cpu: 0.6, pressure: .warning, temp: 70), systemPower: nil, name: \.name)
        let (minute, _) = bucket.finish(net: nil)
        XCTAssertEqual(minute.cpu, 0.4, accuracy: 1e-9)
        XCTAssertEqual(minute.cpuMax, 0.6, accuracy: 1e-9)
        XCTAssertEqual(minute.cpuTempMax, 70)
        XCTAssertEqual(minute.memPressure, MemoryPressure.warning.rawValue)
        XCTAssertEqual(minute.power, 4, "averaged over the ticks that had a reading")
        XCTAssertNil(minute.gpu)
        XCTAssertEqual(minute.netIn, 100)
    }

    func testKeepsTheUnionOfTopProcessesPerMetric() {
        var bucket = MinuteBucket(ts: MinuteBucket.minute(of: t0))
        // 10 processes ranked by CPU, one memory hog with no CPU, one power-hungry, one hidden (other user).
        var processes = (1...10).map { Self.process(pid_t($0), cpu: Double($0)) }
        processes.append(Self.process(50, memory: 1 << 30))
        processes.append(Self.process(60, power: 9))
        processes.append(Self.process(70, cpu: 99, taskInfo: false))
        bucket.add(Self.snapshot(at: t0, cpu: 0.5, processes: processes), systemPower: nil, name: \.name)
        bucket.add(Self.snapshot(at: t0 + 1, cpu: 0.5, processes: Array(processes.prefix(1))), systemPower: nil, name: \.name)
        let (_, kept) = bucket.finish(net: [3: 500], top: 3)
        XCTAssertEqual(Set(kept.map(\.pid)), [10, 9, 8, 50, 60, 3], "top 3 CPU + memory + power + network")
        XCTAssertEqual(kept.first { $0.pid == 10 }?.cpu ?? 0, 5, accuracy: 1e-9, "seen in one of two ticks")
        XCTAssertEqual(kept.first { $0.pid == 3 }?.net, 500)
        XCTAssertNil(kept.first { $0.pid == 10 }?.net)
    }

    func testBundleIsRecorded() {
        var bucket = MinuteBucket(ts: 0)
        bucket.add(Self.snapshot(at: t0, cpu: 0, processes: [Self.process(1, cpu: 1, path: "/Applications/X.app/Contents/MacOS/X")]),
                   systemPower: nil, name: \.name)
        XCTAssertEqual(bucket.finish(net: nil).1.first?.bundle, "/Applications/X.app")
    }

    func testNetRatesNeedTwoReadings() {
        let before = NetReading(date: t0, usage: [ProcessNetUsage(pid: 1, name: "a", bytesIn: 100, bytesOut: 0, rateIn: 0, rateOut: 0),
                                                  ProcessNetUsage(pid: 2, name: "b", bytesIn: 5, bytesOut: 5, rateIn: 0, rateOut: 0)])
        let after = NetReading(date: t0 + 60, usage: [ProcessNetUsage(pid: 1, name: "a", bytesIn: 700, bytesOut: 600, rateIn: 0, rateOut: 0),
                                                      ProcessNetUsage(pid: 3, name: "c", bytesIn: 9, bytesOut: 9, rateIn: 0, rateOut: 0)])
        let rates = after.rates(since: before)
        XCTAssertEqual(rates[1], 20, "1200 bytes over 60 s")
        XCTAssertNil(rates[2], "exited")
        XCTAssertNil(rates[3], "no baseline")
    }
}

final class RefreshIntervalTests: XCTestCase {
    func testStepsUseAFinerGridBelowOneSecond() {
        XCTAssertEqual(RefreshInterval.step(1000, faster: true), 900)
        XCTAssertEqual(RefreshInterval.step(900, faster: false), 1000)
        XCTAssertEqual(RefreshInterval.step(1000, faster: false), 1500)
        XCTAssertEqual(RefreshInterval.step(1500, faster: true), 1000)
        XCTAssertEqual(RefreshInterval.step(1250, faster: true), 1000, "snaps onto the grid")
        XCTAssertEqual(RefreshInterval.step(1250, faster: false), 1500)
        XCTAssertEqual(RefreshInterval.step(950, faster: true), 900)
        XCTAssertEqual(RefreshInterval.step(100, faster: true), 100, "clamped")
        XCTAssertEqual(RefreshInterval.step(10_000, faster: false), 10_000)
    }

    func testParsingAcceptsUnitsAndClamps() {
        XCTAssertEqual(RefreshInterval.parse("250"), 250)
        XCTAssertEqual(RefreshInterval.parse(" 250 ms"), 250)
        XCTAssertEqual(RefreshInterval.parse("1.5s"), 1500)
        XCTAssertEqual(RefreshInterval.parse("2 s"), 2000)
        XCTAssertEqual(RefreshInterval.parse("5"), 100, "snaps to the lower limit")
        XCTAssertEqual(RefreshInterval.parse("99999"), 10_000)
        XCTAssertNil(RefreshInterval.parse("fast"))
    }

    func testSettingStoresSeconds() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "RefreshIntervalTests"))
        defer { defaults.removePersistentDomain(forName: "RefreshIntervalTests") }
        RefreshInterval.set(250, defaults)
        XCTAssertEqual(defaults.double(forKey: SettingsKey.refreshInterval), 0.25)
        RefreshInterval.set(20, defaults)
        XCTAssertEqual(defaults.double(forKey: SettingsKey.refreshInterval), 0.1)
    }
}

final class TimelineTests: XCTestCase {
    private func v(_ minute: Int, _ value: Double = 1) -> HistoryValue {
        HistoryValue(date: Date(timeIntervalSince1970: TimeInterval(minute * 60)), value: value)
    }

    func testGapsBreakTheLine() {
        let segments = TimelineSegments.split([v(0), v(1), v(2), v(10), v(11)], maxGap: 150)
        XCTAssertEqual(segments.map(\.count), [3, 2])
        XCTAssertTrue(TimelineSegments.split([], maxGap: 60).isEmpty)
    }

    func testValueLookupStaysInsideTheGap() {
        let values = [v(0, 1), v(1, 2), v(5, 3)]
        XCTAssertEqual(TimelineSegments.value(in: values, at: Date(timeIntervalSince1970: 90), maxGap: 60), 2)
        XCTAssertNil(TimelineSegments.value(in: values, at: Date(timeIntervalSince1970: 200), maxGap: 60), "in the gap")
        XCTAssertNil(TimelineSegments.value(in: values, at: Date(timeIntervalSince1970: -1), maxGap: 60))
    }

    func testRangesUseAboutThreeHundredSixtyMinuteBuckets() {
        XCTAssertEqual(HistoryRange.hour.bucket, 60)
        XCTAssertEqual(HistoryRange.day.bucket, 240)
        XCTAssertEqual(HistoryRange.month.bucket, 7200)
    }

    func testTenthSectionGetsCommandZero() {
        XCTAssertEqual(AppSection.allCases.count, 10)
        XCTAssertEqual(AppSection.shortcut(index: 0), KeyEquivalent("1"))
        XCTAssertEqual(AppSection.shortcut(index: 9), KeyEquivalent("0"))
    }
}
