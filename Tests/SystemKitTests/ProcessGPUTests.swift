import XCTest
@testable import SystemKit

final class ProcessGPUTests: XCTestCase {
    func testParsesCreatorPID() {
        XCTAssertEqual(ProcessGPUSampler.pid(fromCreator: "pid 412, WindowServer"), 412)
        XCTAssertEqual(ProcessGPUSampler.pid(fromCreator: "pid 7"), 7)
        XCTAssertNil(ProcessGPUSampler.pid(fromCreator: "WindowServer"))
        XCTAssertNil(ProcessGPUSampler.pid(fromCreator: "pid , x"))
    }

    func testLiveSampleReportsGPUClients() throws {
        let sampler = ProcessGPUSampler()
        let first = sampler.sample()
        try XCTSkipIf(first.isEmpty, "This Mac exposes no per-process GPU counters")
        Thread.sleep(forTimeInterval: 0.3)
        let second = sampler.sample()
        XCTAssertFalse(second.isEmpty)
        for usage in second.values {
            XCTAssertGreaterThanOrEqual(usage.utilization, 0)
            XCTAssertGreaterThan(usage.gpuTime, 0)
        }
        let top = second.sorted { $0.value.gpuTime > $1.value.gpuTime }.prefix(5)
        print(top.map { "pid \($0.key): \(String(format: "%.1f", $0.value.utilization * 100))% · \(String(format: "%.1f", $0.value.gpuTime)) s" })
    }
}
