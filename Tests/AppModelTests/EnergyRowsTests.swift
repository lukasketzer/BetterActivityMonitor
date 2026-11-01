import Foundation
import XCTest
@testable import BetterActivityMonitor
@testable import SystemKit

final class EnergyRowsTests: XCTestCase {
    private func entry(_ pid: pid_t, path: String, power: Double, energy: Double = 0, taskInfo: Bool = true) -> ProcessEntry {
        var e = ProcessEntry(pid: pid, ppid: 1, uid: 501, user: "me", name: (path as NSString).lastPathComponent,
                             path: path, state: .running, nice: 0, startTime: .distantPast, hasTaskInfo: taskInfo,
                             cpu: 0, cpuTime: 0, memory: 0, resident: 0, threads: 1, diskReadRate: 0,
                             diskWriteRate: 0, diskReadTotal: 0, diskWriteTotal: 0, idleWakeupsPerSecond: 1)
        e.power = power
        e.energyTotal = energy
        return e
    }

    func testBundlePathIsTheOutermostApp() {
        XCTAssertEqual(AppBundle.path(forExecutable: "/Applications/Chrome.app/Contents/Frameworks/X.framework/Helpers/Helper.app/Contents/MacOS/Helper"),
                       "/Applications/Chrome.app")
        XCTAssertNil(AppBundle.path(forExecutable: "/usr/sbin/syslogd"))
        XCTAssertEqual(AppBundle.name(ofBundle: "/Applications/Google Chrome.app"), "Google Chrome")
    }

    func testHelpersAddUpUnderTheirApp() throws {
        let processes = [
            entry(10, path: "/Applications/Chrome.app/Contents/MacOS/Chrome", power: 1, energy: 100),
            entry(11, path: "/Applications/Chrome.app/Contents/Frameworks/H.app/Contents/MacOS/H", power: 3, energy: 50),
            entry(20, path: "/usr/sbin/syslogd", power: 0.5),
        ]
        let apps: [pid_t: AppInfo] = [10: AppInfo(name: "Google Chrome", icon: nil, bundleIdentifier: nil, isRegular: true)]
        let groups = EnergyRows.sorted(EnergyRows.groups(processes, apps: apps, displayName: \.name), by: .power)
        XCTAssertEqual(groups.map(\.name), ["Google Chrome", "syslogd"])
        let chrome = try XCTUnwrap(groups.first)
        XCTAssertEqual(chrome.power, 4)
        XCTAssertEqual(chrome.energyTotal, 150)
        XCTAssertEqual(chrome.wakeups, 2)
        XCTAssertEqual(chrome.leadPID, 10, "the app's own process leads, even when a helper uses more")
        XCTAssertEqual(Set(chrome.pids), [10, 11])
    }

    func testWithoutTheAppRunningTheBusiestHelperLeads() throws {
        let processes = [
            entry(30, path: "/Applications/Tool.app/Contents/MacOS/a", power: 1),
            entry(31, path: "/Applications/Tool.app/Contents/MacOS/b", power: 2),
        ]
        let group = try XCTUnwrap(EnergyRows.groups(processes, apps: [:], displayName: \.name).first)
        XCTAssertEqual(group.name, "Tool")
        XCTAssertEqual(group.leadPID, 31)
    }

    func testOtherUsersProcessesHaveNoEnergyInfo() throws {
        let group = try XCTUnwrap(EnergyRows.groups([entry(1, path: "/sbin/launchd", power: 0, taskInfo: false)],
                                                    apps: [:], displayName: \.name).first)
        XCTAssertFalse(group.hasTaskInfo)
    }

    func testSortByEnergyAndTieBreakByName() {
        let groups = [EnergyGroup(id: "b", name: "b", leadPID: 1, pids: [1], energyTotal: 5),
                      EnergyGroup(id: "a", name: "a", leadPID: 2, pids: [2], energyTotal: 5),
                      EnergyGroup(id: "c", name: "c", leadPID: 3, pids: [3], energyTotal: 9)]
        XCTAssertEqual(EnergyRows.sorted(groups, by: .energy).map(\.name), ["c", "a", "b"])
    }

    func testFormatting() {
        XCTAssertEqual(Fmt.watts(0), "0 W")
        XCTAssertEqual(Fmt.watts(0.004), "4 mW")
        XCTAssertEqual(Fmt.watts(1.234), "1.23 W")
        XCTAssertEqual(Fmt.watts(12.34), "12.3 W")
        XCTAssertEqual(Fmt.energy(120), "120 J")
        XCTAssertEqual(Fmt.energy(7200), "2.00 Wh")
    }

    func testPowerColumnShowsSubtreeWhenCollapsed() {
        var row = ProcessRow.build(from: entry(5, path: "/bin/x", power: 0.5), app: nil, totalMemory: 0, cpuDivisor: 1,
                                   preventsSleep: true)
        XCTAssertEqual(ProcessColumn.power.text(row), "0.50 W")
        XCTAssertEqual(ProcessColumn.preventsSleep.text(row), "Preventing")
        row.isCollapsed = true
        row.subtreePower = 2
        XCTAssertEqual(ProcessColumn.power.text(row), "2.00 W")
    }
}
