import Foundation
import XCTest
@testable import BetterActivityMonitor
@testable import SystemKit

final class ProcessRowTests: XCTestCase {
    func row(_ pid: pid_t, parent: pid_t = 1, name: String? = nil, uid: uid_t = 501, cpu: Double = 0,
             memory: UInt64 = 0, isApp: Bool = false, readRate: Double = 0) -> ProcessRow {
        ProcessRow(
            pid: pid, ppid: parent, name: name ?? "proc\(pid)", user: uid == 0 ? "root" : "me", uid: uid,
            path: "/usr/bin/\(name ?? "proc\(pid)")", state: .sleeping, nice: 0, startTime: .distantPast,
            hasTaskInfo: true, cpu: cpu, cpuTime: 0, memory: memory, memoryFraction: 0, resident: memory,
            threads: 1, diskReadRate: readRate, diskWriteRate: 0, diskReadTotal: 0, diskWriteTotal: 0,
            wakeups: 0, isApp: isApp
        )
    }

    // launchd(1) ── shell(10) ── tool(11)
    //            └─ app(20)
    lazy var processes = [
        row(1, parent: 0, name: "launchd", uid: 0, cpu: 1, memory: 10),
        row(10, name: "shell", cpu: 2, memory: 100),
        row(11, parent: 10, name: "tool", cpu: 30, memory: 1000),
        row(20, name: "Safari", cpu: 5, memory: 500, isApp: true),
    ]

    let byCPU = [KeyPathComparator(\ProcessRow.cpu, order: .reverse)]

    // MARK: matches

    func testEmptyQueryMatchesEverything() {
        XCTAssertTrue(ProcessRowBuilder.matches(row(5), query: "", regex: nil))
    }

    func testPlainQueryIsCaseInsensitiveOnNamePathAndUser() {
        let safari = row(20, name: "Safari")
        XCTAssertTrue(ProcessRowBuilder.matches(safari, query: "safa", regex: nil))
        XCTAssertTrue(ProcessRowBuilder.matches(safari, query: "/USR/bin", regex: nil))
        XCTAssertTrue(ProcessRowBuilder.matches(row(3, uid: 0), query: "root", regex: nil))
        XCTAssertFalse(ProcessRowBuilder.matches(safari, query: "chrome", regex: nil))
    }

    func testPlainQueryMatchesWholePIDOnly() {
        XCTAssertTrue(ProcessRowBuilder.matches(row(1234), query: "1234", regex: nil))
        XCTAssertFalse(ProcessRowBuilder.matches(row(1234), query: "123", regex: nil))
    }

    func testRegexQuery() throws {
        let regex = try Regex("^proc[0-9]$")
        XCTAssertTrue(ProcessRowBuilder.matches(row(7), query: "^proc[0-9]$", regex: regex))
        XCTAssertFalse(ProcessRowBuilder.matches(row(77), query: "^proc[0-9]$", regex: regex))
    }

    // MARK: scopes

    func testScopes() {
        let mine = row(10, uid: 501), root = row(1, uid: 0), app = row(20, isApp: true)
        let busy = row(30, cpu: 0.5), reading = row(31, readRate: 10), idle = row(32)

        XCTAssertTrue([mine, root, app].allSatisfy { ProcessRowBuilder.inScope($0, scope: .all, myUID: 501) })
        XCTAssertTrue(ProcessRowBuilder.inScope(mine, scope: .mine, myUID: 501))
        XCTAssertFalse(ProcessRowBuilder.inScope(root, scope: .mine, myUID: 501))
        XCTAssertTrue(ProcessRowBuilder.inScope(root, scope: .system, myUID: 501))
        XCTAssertFalse(ProcessRowBuilder.inScope(mine, scope: .system, myUID: 501))
        XCTAssertTrue(ProcessRowBuilder.inScope(app, scope: .apps, myUID: 501))
        XCTAssertFalse(ProcessRowBuilder.inScope(mine, scope: .apps, myUID: 501))
        XCTAssertTrue(ProcessRowBuilder.inScope(busy, scope: .active, myUID: 501))
        XCTAssertTrue(ProcessRowBuilder.inScope(reading, scope: .active, myUID: 501))
        XCTAssertFalse(ProcessRowBuilder.inScope(idle, scope: .active, myUID: 501))
    }

    // MARK: rows

    func testFlatModeFiltersAndSorts() {
        let rows = ProcessRowBuilder.rows(processes, matching: { $0.cpu > 1 }, sort: byCPU, tree: false, collapsed: [])
        XCTAssertEqual(rows.map(\.pid), [11, 20, 10])
        XCTAssertTrue(rows.allSatisfy { $0.depth == 0 })
    }

    func testTreeModeNestsChildrenAndSortsSiblings() {
        let rows = ProcessRowBuilder.rows(processes, matching: { _ in true }, sort: byCPU, tree: true, collapsed: [])
        XCTAssertEqual(rows.map(\.pid), [1, 20, 10, 11], "siblings by CPU: Safari (5) before shell (2)")
        XCTAssertEqual(rows.map(\.depth), [0, 1, 1, 2])
        XCTAssertEqual(rows.map(\.hasChildren), [true, false, true, false])
    }

    func testTreeFilterKeepsAncestorsOfMatches() {
        let rows = ProcessRowBuilder.rows(processes, matching: { $0.name == "tool" }, sort: byCPU, tree: true, collapsed: [])
        XCTAssertEqual(rows.map(\.pid), [1, 10, 11])
        XCTAssertEqual(rows.map(\.depth), [0, 1, 2])
    }

    func testCollapsedParentHidesChildrenAndSumsSubtree() throws {
        let rows = ProcessRowBuilder.rows(processes, matching: { _ in true }, sort: byCPU, tree: true, collapsed: [10])
        XCTAssertEqual(rows.map(\.pid), [1, 20, 10])
        let shell = try XCTUnwrap(rows.last)
        XCTAssertTrue(shell.isCollapsed)
        XCTAssertEqual(shell.subtreeCPU, 32)
        XCTAssertEqual(shell.subtreeMemory, 1100)
    }

    func testOrphansAndSelfParentedProcessesBecomeRoots() {
        let odd = [row(0, parent: 0, name: "kernel_task"), row(50, parent: 999, name: "orphan")]
        let rows = ProcessRowBuilder.rows(odd, matching: { _ in true }, sort: [KeyPathComparator(\ProcessRow.pid)],
                                          tree: true, collapsed: [])
        XCTAssertEqual(rows.map(\.pid), [0, 50])
        XCTAssertEqual(rows.map(\.depth), [0, 0])
    }

    func testBuildUsesAppNameAndScalesCPU() {
        let entry = ProcessEntry(
            pid: 42, ppid: 1, uid: 501, user: "me", name: "com.apple.Safari", path: "/Applications/Safari.app",
            state: .running, nice: 0, startTime: .distantPast, hasTaskInfo: true, cpu: 200, cpuTime: 1,
            memory: 512, resident: 512, threads: 4, diskReadRate: 0, diskWriteRate: 0, diskReadTotal: 0,
            diskWriteTotal: 0, idleWakeupsPerSecond: 0
        )
        let app = AppInfo(name: "Safari", icon: nil, bundleIdentifier: "com.apple.Safari", isRegular: true)
        let built = ProcessRow.build(from: entry, app: app, totalMemory: 1024, cpuDivisor: 4)
        XCTAssertEqual(built.name, "Safari")
        XCTAssertEqual(built.cpu, 50)
        XCTAssertEqual(built.memoryFraction, 0.5)
        XCTAssertTrue(built.isApp)

        let bare = ProcessRow.build(from: entry, app: nil, totalMemory: 0, cpuDivisor: 1)
        XCTAssertEqual(bare.name, "com.apple.Safari")
        XCTAssertEqual(bare.memoryFraction, 0, "no division by zero memory")
        XCTAssertFalse(bare.isApp)
    }
}
