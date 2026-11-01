import Darwin
import Foundation
import IOKit.pwr_mgt
import XCTest
@testable import SystemKit

final class EnergyTests: XCTestCase {
    /// A busy second on one core must show up as watts on this process.
    func testBusyProcessReportsPower() throws {
        let sampler = ProcessSampler()
        _ = sampler.sample()
        let start = Date()
        var x = 1.0
        while Date().timeIntervalSince(start) < 0.5 { x = x.squareRoot() + 1 }
        let me = try XCTUnwrap(sampler.sample().first { $0.pid == getpid() })
        XCTAssertGreaterThan(x, 0)
        XCTAssertGreaterThan(me.power, 0.05, "Apple Silicon reports per-process energy in ri_energy_nj")
        XCTAssertLessThan(me.power, 100)
        XCTAssertGreaterThan(me.energyTotal, 0)
    }

    func testOwnAssertionIsListed() throws {
        var id: IOPMAssertionID = 0
        let created = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                                  IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                  "BetterActivityMonitor test" as CFString, &id)
        XCTAssertEqual(created, kIOReturnSuccess)
        defer { IOPMAssertionRelease(id) }
        let mine = try XCTUnwrap(PowerAssertionSampler.read()[getpid()])
        let assertion = try XCTUnwrap(mine.first { $0.name == "BetterActivityMonitor test" })
        XCTAssertEqual(assertion.type, "PreventUserIdleSystemSleep")
        XCTAssertTrue(assertion.preventsSleep)
        XCTAssertEqual(assertion.effect, "Prevents idle sleep")
    }

    func testAssertionsAreCached() {
        let sampler = PowerAssertionSampler()
        let now = Date()
        _ = sampler.sample(now: now)
        var id: IOPMAssertionID = 0
        IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                    IOPMAssertionLevel(kIOPMAssertionLevelOn), "cached test" as CFString, &id)
        defer { IOPMAssertionRelease(id) }
        let soon = sampler.sample(now: now.addingTimeInterval(1))
        XCTAssertFalse(soon[getpid()]?.contains { $0.name == "cached test" } ?? false, "reused within 5 s")
        let later = sampler.sample(now: now.addingTimeInterval(6))
        XCTAssertTrue(later[getpid()]?.contains { $0.name == "cached test" } ?? false)
    }
}
