import Foundation
import XCTest
@testable import SystemKit

final class HistoryDatabaseTests: XCTestCase {
    private let t0 = 1_800_000_000 / 60 * 60

    private func minute(_ i: Int, cpu: Double = 0.5, gpu: Double? = nil, temp: Double? = nil) -> SystemMinute {
        SystemMinute(ts: t0 + i * 60, cpu: cpu, cpuUser: cpu / 2, cpuSystem: cpu / 2, cpuMax: cpu + 0.1, memUsed: 0.4,
                     memPressure: 1, swap: 0, gpu: gpu, netIn: 100, netOut: 50, diskRead: 10, diskWrite: 20,
                     cpuTempMax: temp, battery: nil, power: 5)
    }

    private func date(_ i: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(t0 + i * 60)) }

    func testSeriesReturnsMinutesAndSkipsNulls() async {
        let store = HistoryDatabase(url: nil)
        for i in 0..<5 { await store.append(minute(i, cpu: Double(i) / 10, gpu: i == 2 ? 0.3 : nil), processes: []) }
        let cpu = await store.series(.cpu, from: date(0), to: date(5))
        XCTAssertEqual(cpu.map(\.value), [0, 0.1, 0.2, 0.3, 0.4])
        XCTAssertEqual(cpu.first?.date, date(0))
        let gpu = await store.series(.gpu, from: date(0), to: date(5))
        XCTAssertEqual(gpu.map(\.value), [0.3], "minutes without a GPU reading are left out, not zero")
    }

    func testBucketsAverageButKeepPeaks() async {
        let store = HistoryDatabase(url: nil)
        for i in 0..<10 { await store.append(minute(i, cpu: i < 5 ? 0.2 : 0.6, temp: Double(50 + i)), processes: []) }
        let cpu = await store.series(.cpu, from: date(0), to: date(10), bucket: 300)
        XCTAssertEqual(cpu.count, 2)
        XCTAssertEqual(cpu[0].value, 0.2, accuracy: 1e-9)
        XCTAssertEqual(cpu[1].value, 0.6, accuracy: 1e-9)
        let temp = await store.series(.cpuTempMax, from: date(0), to: date(10), bucket: 300)
        XCTAssertEqual(temp.map(\.value), [54, 59], "peaks stay peaks")
    }

    func testRewritingAMinuteReplacesIt() async {
        let store = HistoryDatabase(url: nil)
        let p = ProcessMinute(ts: t0, pid: 1, name: "a", bundle: nil, cpu: 1, memory: 1, disk: 0, net: nil, power: 0)
        await store.append(minute(0, cpu: 0.1), processes: [p, p])
        await store.append(minute(0, cpu: 0.9), processes: [p])
        let minutes = await store.minuteCount()
        let cpu = await store.series(.cpu, from: date(0), to: date(1))
        let processes = await store.processes(at: date(0))
        XCTAssertEqual(minutes, 1)
        XCTAssertEqual(cpu.map(\.value), [0.9])
        XCTAssertEqual(processes.count, 1)
    }

    func testTopProcessesSumHelpersUnderTheirApp() async throws {
        let store = HistoryDatabase(url: nil)
        let chrome = "/Applications/Google Chrome.app"
        for i in 0..<4 {
            await store.append(minute(i), processes: [
                ProcessMinute(ts: t0 + i * 60, pid: 10, name: "Google Chrome", bundle: chrome, cpu: 10, memory: 100,
                              disk: 0, net: 1000, power: 1),
                ProcessMinute(ts: t0 + i * 60, pid: 11 + pid_t(i), name: "Google Chrome Helper", bundle: chrome, cpu: 30,
                              memory: 300, disk: 0, net: nil, power: 2),
                ProcessMinute(ts: t0 + i * 60, pid: 20, name: "kernel_task", bundle: nil, cpu: i == 0 ? 80 : 0,
                              memory: 10, disk: 5, net: nil, power: 0.5),
            ])
        }
        let byCPU = await store.topProcesses(from: date(0), to: date(4), by: .cpu)
        XCTAssertEqual(byCPU.map(\.name), ["Google Chrome", "kernel_task"])
        let app = try XCTUnwrap(byCPU.first)
        XCTAssertEqual(app.cpu, 40, accuracy: 1e-9, "10 + 30 % every minute")
        XCTAssertEqual(app.memoryPeak, 400)
        XCTAssertEqual(app.netBytes, 4 * 1000 * 60, accuracy: 1e-6)
        XCTAssertEqual(app.energy, 4 * 3 * 60, accuracy: 1e-6, "W × 60 s per minute")
        XCTAssertEqual(app.minutes, 4)
        XCTAssertEqual(app.pid, 14, "newest minute's pid")
        XCTAssertEqual(byCPU.last?.cpu ?? 0, 20, accuracy: 1e-9, "80 % for one of four minutes")

        let byDisk = await store.topProcesses(from: date(0), to: date(4), by: .disk)
        XCTAssertEqual(byDisk.first?.name, "kernel_task")
    }

    func testPruneDropsOldMinutes() async {
        let store = HistoryDatabase(url: nil)
        for i in 0..<10 {
            await store.append(minute(i), processes: [ProcessMinute(ts: t0 + i * 60, pid: 1, name: "a", bundle: nil,
                                                                    cpu: 1, memory: 1, disk: 0, net: nil, power: 0)])
        }
        await store.prune(olderThan: date(6))
        let count = await store.minuteCount()
        let gone = await store.processes(at: date(5))
        let kept = await store.processes(at: date(6))
        XCTAssertEqual(count, 4)
        XCTAssertTrue(gone.isEmpty)
        XCTAssertEqual(kept.count, 1)
        await store.clear()
        let cleared = await store.minuteCount()
        XCTAssertEqual(cleared, 0)
    }

    /// 30 days at 15 processes a minute must stay a reasonable file, and range queries quick.
    func testThirtyDaysFitOnDisk() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = HistoryDatabase(url: dir.appendingPathComponent("history.sqlite"))
        let days = 30
        for i in 0..<(days * 1440) {
            let processes = (0..<15).map { (k: Int) -> ProcessMinute in
                let bundle: String? = k < 5 ? "/Applications/App \(k).app" : nil
                let value = Double(k)
                return ProcessMinute(ts: t0 + i * 60, pid: pid_t(100 + k), name: "process number \(k)", bundle: bundle,
                                     cpu: value, memory: UInt64(k) << 20, disk: value * 100, net: value * 10, power: value / 10)
            }
            await store.append(minute(i, cpu: Double(i % 100) / 100), processes: processes)
        }
        let size = await store.size()
        print("history size for \(days) days:", size / 1_000_000, "MB")
        XCTAssertLessThan(size, 120_000_000)

        let start = Date()
        let series = await store.series(.cpu, from: date(0), to: date(days * 1440), bucket: 60 * 90)
        let top = await store.topProcesses(from: date(0), to: date(days * 1440), by: .cpu)
        let elapsed = Date().timeIntervalSince(start)
        print("30-day series + top processes query:", Int(elapsed * 1000), "ms")
        // t0 isn't aligned to 90-minute buckets, so the range touches one partial bucket at each end.
        XCTAssertTrue((days * 1440 / 90)...(days * 1440 / 90 + 1) ~= series.count, "\(series.count) buckets")
        XCTAssertEqual(top.count, 15)
        XCTAssertLessThan(elapsed, 3)
    }
}
