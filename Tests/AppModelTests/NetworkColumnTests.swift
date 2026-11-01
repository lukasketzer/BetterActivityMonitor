import Foundation
import XCTest
@testable import BetterActivityMonitor
@testable import SystemKit

@MainActor
final class NetworkColumnTests: XCTestCase {
    func testDemandRunsTheCostliestRequestedMode() {
        var demand = ConnectionDemand()
        XCTAssertEqual(demand.effective, .off)
        XCTAssertTrue(demand.set(.processes, for: .processTable))
        XCTAssertTrue(demand.set(.all, for: .networkPage))
        XCTAssertEqual(demand.effective, .all)
        XCTAssertFalse(demand.set(.processes, for: .history), "already covered by .all")
        XCTAssertTrue(demand.set(.off, for: .networkPage))
        XCTAssertEqual(demand.effective, .processes, "the table still needs per-process counters")
        XCTAssertFalse(demand.set(.off, for: .processTable), "history still asks for .processes")
        XCTAssertTrue(demand.set(.off, for: .history))
        XCTAssertEqual(demand.effective, .off)
    }

    func testNetworkColumnsFormatRatesAndSubtrees() {
        var row = ProcessRow(
            pid: 1, ppid: 0, name: "a", user: "me", uid: 501, path: "", state: .running, nice: 0,
            startTime: .distantPast, hasTaskInfo: false, cpu: 0, cpuTime: 0, memory: 0, memoryFraction: 0,
            resident: 0, threads: 1, diskReadRate: 0, diskWriteRate: 0, diskReadTotal: 0, diskWriteTotal: 0,
            wakeups: 0, netRateIn: 2048, netRateOut: 0, netTotalIn: 4096, netTotalOut: 0, isApp: false)
        XCTAssertNotEqual(ProcessColumn.netIn.text(row), "—", "nettop sees other users' processes too")
        XCTAssertEqual(ProcessColumn.netOut.text(row), "0")
        XCTAssertEqual(ProcessColumn.netInTotal.text(row), Fmt.bytes(UInt64(4096)))
        row.isCollapsed = true
        row.subtreeNetIn = 1_000_000
        XCTAssertEqual(ProcessColumn.netIn.text(row), Fmt.rate(1_000_000))
    }

    func testNewColumnsStartAtTheirDefaultForSavedLayouts() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "NetworkColumnTests"))
        defer { defaults.removePersistentDomain(forName: "NetworkColumnTests") }
        // A layout saved before the network columns existed: the user had shown `path`.
        defaults.set(["resident", "readTotal"], forKey: "ProcessTable.hiddenColumns")
        let hidden = ProcessTableController.hiddenColumns(defaults)
        XCTAssertFalse(hidden.contains("path"), "the user's choice is kept")
        XCTAssertTrue(hidden.contains("netInTotal"), "new hidden-by-default columns stay hidden")
        XCTAssertTrue(hidden.contains("netIn"), "network columns cost a nettop run per tick, so they start hidden")

        defaults.set(ProcessColumn.allCases.map(\.rawValue), forKey: "ProcessTable.knownColumns")
        XCTAssertFalse(ProcessTableController.hiddenColumns(defaults).contains("netIn"),
                       "once known, only the saved list counts")
    }
}
