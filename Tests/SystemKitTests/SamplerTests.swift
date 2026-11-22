import Darwin
import XCTest
import SystemKit

final class SamplerTests: XCTestCase {
    func testSnapshotValuesAreSane() async throws {
        let monitor = SystemMonitor()
        _ = await monitor.sample()
        try await Task.sleep(for: .milliseconds(500))
        let s = await monitor.sample()

        XCTAssertGreaterThan(s.cpu.cores.count, 0)
        XCTAssert((0...1.0001).contains(s.cpu.total))
        for core in s.cpu.cores { XCTAssert((0...1.0001).contains(core.total)) }
        XCTAssertEqual(s.cpu.loadAverage.count, 3)

        XCTAssertGreaterThan(s.memory.total, 0)
        XCTAssertLessThanOrEqual(s.memory.used, s.memory.total)
        XCTAssertLessThanOrEqual(s.memory.swapUsed, s.memory.swapTotal)

        XCTAssertGreaterThanOrEqual(s.network.rateIn, 0)
        XCTAssertGreaterThanOrEqual(s.disks.readRate, 0)
        XCTAssertFalse(s.disks.volumes.isEmpty)
    }

    func testOwnProcessIsVisibleWithFullInfo() async {
        let s = await SystemMonitor().sample()
        let me = try? XCTUnwrap(s.processes.first { $0.pid == getpid() })
        XCTAssertNotNil(me)
        XCTAssertTrue(me?.hasTaskInfo ?? false)
        XCTAssertGreaterThan(me?.memory ?? 0, 0)
        XCTAssertGreaterThan(me?.threads ?? 0, 0)
        XCTAssertEqual(me?.uid, getuid())
        XCTAssertTrue(s.processes.contains { $0.pid == 1 }, "launchd should always be listed")
    }

    /// Idle processes reuse their last task info instead of asking the kernel again; they must keep
    /// reporting the same thread count and memory as when they were read in full.
    func testIdleProcessesKeepTheirTaskInfo() async throws {
        let monitor = SystemMonitor()
        let first = await monitor.sample().processes
        try await Task.sleep(for: .milliseconds(300))
        let second = await monitor.sample().processes
        let before = Dictionary(first.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        var idle = 0
        for p in second where p.hasTaskInfo {
            guard let old = before[p.pid], old.startTime == p.startTime, old.cpuTime == p.cpuTime else { continue }
            idle += 1
            XCTAssertEqual(p.threads, old.threads, "\(p.name) (\(p.pid)) lost its thread count")
            XCTAssertGreaterThan(p.threads, 0, "\(p.name) (\(p.pid))")
            XCTAssertNotEqual(p.state, .running, "\(p.name) used no CPU but is reported running")
        }
        XCTAssertGreaterThan(idle, 10, "expected some idle processes between two samples")
    }

    func testNetworkCountersAreMonotonic() async throws {
        let monitor = SystemMonitor()
        let a = await monitor.sample().network
        try await Task.sleep(for: .milliseconds(200))
        let b = await monitor.sample().network
        for iface in b.interfaces {
            guard let before = a.interfaces.first(where: { $0.name == iface.name }) else { continue }
            XCTAssertGreaterThanOrEqual(iface.bytesIn, before.bytesIn, iface.name)
            XCTAssertGreaterThanOrEqual(iface.bytesOut, before.bytesOut, iface.name)
        }
    }

    func testProcessDetailsForSelf() {
        let d = ProcessDetails.fetch(pid: getpid())
        XCTAssertFalse(d.arguments.isEmpty)
        XCTAssertFalse(d.executable.isEmpty)
        XCTAssertNotNil(d.workingDirectory)
        XCTAssertNotNil(d.openFiles)
    }

    func testSignalToMissingProcessFails() {
        // PID far above any real one.
        if case .success = ProcessControl.send(0, to: 99_999_999) { XCTFail("expected failure") }
    }
}
