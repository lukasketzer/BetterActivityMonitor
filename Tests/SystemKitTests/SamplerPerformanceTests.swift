import Darwin
import XCTest
import SystemKit

/// Cost budgets for data collection. Run optimized for representative numbers:
///   swift test -c release --filter SamplerPerformanceTests
/// Budgets hold in debug builds too; release numbers are roughly 2–3x lower.
final class SamplerPerformanceTests: XCTestCase {
    /// Collects `ticks` samples 250 ms apart and returns per-sampler wall times plus process CPU time per tick.
    private func run(ticks: Int, detailedSensors: Bool = false) async throws -> (timings: [String: [Double]], cpuMsPerTick: Double) {
        let monitor = SystemMonitor()
        await monitor.setDetailedSensors(detailedSensors)
        _ = await monitor.sample()  // warm-up: caches, SMC key enumeration
        var timings: [String: [Double]] = [:]
        var cpu = 0.0
        for _ in 0..<ticks {
            try await Task.sleep(for: .milliseconds(250))
            let start = clock()
            _ = await monitor.sample()
            cpu += Double(clock() - start) / Double(CLOCKS_PER_SEC) * 1000
            for (name, ms) in await monitor.lastTimings { timings[name, default: []].append(ms) }
        }
        return (timings, cpu / Double(ticks))
    }

    private func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }

    func testPerTickCostStaysLow() async throws {
        let (timings, cpuMsPerTick) = try await run(ticks: 16)
        for (name, values) in timings.sorted(by: { $0.key < $1.key }) {
            print(String(format: "%-10@ median %6.2f ms  max %6.2f ms", name as NSString, median(values), values.max()!))
        }
        print(String(format: "process CPU per tick: %.2f ms", cpuMsPerTick))

        // At a 1 s refresh, 15 ms per tick is 1.5% of one core.
        XCTAssertLessThan(cpuMsPerTick, 15, "sampling got more expensive")
        let budgets: [String: Double] = [
            "processes": 12, "cpu": 1, "memory": 1, "network": 2, "disks": 2, "gpu": 1.5, "battery": 1,
        ]
        for (name, budget) in budgets {
            let values = try XCTUnwrap(timings[name], "missing timing for \(name)")
            XCTAssertLessThan(median(values), budget, "\(name) median exceeded its budget")
        }
    }

    /// Temperature reads go through the SMC (~0.6 ms per key); the routine set must stay small.
    func testRoutineSensorReadIsCheap() async throws {
        let (timings, _) = try await run(ticks: 16)
        let reads = (timings["sensors"] ?? []).filter { $0 > 0.01 }  // the sampler throttles itself
        guard let worst = reads.max() else { throw XCTSkip("no temperature sensors on this Mac") }
        XCTAssertLessThan(worst, 40, "routine sensor read took \(worst) ms")
    }

    func testSensorsAreThrottled() async throws {
        let (timings, _) = try await run(ticks: 8)
        let reads = (timings["sensors"] ?? []).filter { $0 > 0.01 }.count
        XCTAssertLessThanOrEqual(reads, 3, "sensors should be read at most every few seconds, got \(reads) reads in 2 s")
    }
}
