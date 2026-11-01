import Foundation
import XCTest

/// End-to-end CPU budgets for the real app, per screen, with its window frontmost.
/// Opt-in because it launches the GUI app and takes a few minutes:
///   scripts/bundle.sh && BAM_APP_PERF=1 swift test --filter AppCPUTests
/// Background load on the machine adds noise (±4 points observed), so budgets leave headroom.
final class AppCPUTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let app = root.appendingPathComponent("build/BetterActivityMonitor.app")
    private let warmup: TimeInterval = 12
    private let window: TimeInterval = 20

    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["BAM_APP_PERF"] != nil else {
            throw XCTSkip("set BAM_APP_PERF=1 to run app CPU tests")
        }
        guard FileManager.default.fileExists(atPath: Self.app.path) else {
            throw XCTSkip("build the app first: scripts/bundle.sh")
        }
    }

    func testOverview() throws { try assertCPU(screen: "overview", below: 15) }
    func testProcesses() throws { try assertCPU(screen: "processes", below: 15) }
    func testCPU() throws { try assertCPU(screen: "cpu", below: 10) }
    func testMemory() throws { try assertCPU(screen: "memory", below: 10) }
    func testSensors() throws { try assertCPU(screen: "sensors", below: 12) }
    func testEnergy() throws { try assertCPU(screen: "energy", below: 12) }
    /// The fastest interval the toolbar allows. A launch argument overrides the stored setting
    /// (NSArgumentDomain) without changing it. Recorded rather than tight: 10 ticks a second is the user's call.
    func testOverviewAt100ms() throws { try assertCPU(screen: "overview", below: 60, args: ["-refreshInterval", "0.1"]) }

    private func assertCPU(screen: String, below budget: Double, args: [String] = []) throws {
        kill()
        try shell("/usr/bin/open", ["-n", "--env", "BAM_START_SECTION=\(screen)", Self.app.path]
            + (args.isEmpty ? [] : ["--args"] + args))
        defer { kill() }
        Thread.sleep(forTimeInterval: warmup)
        let pid = try XCTUnwrap(Int32(try shell("/usr/bin/pgrep", ["-f", "MacOS/BetterActivityMonitor"])
            .split(separator: "\n").first.map(String.init) ?? ""), "app did not start")
        let start = try cpuSeconds(pid)
        Thread.sleep(forTimeInterval: window)
        let percent = (try cpuSeconds(pid) - start) / window * 100
        print(String(format: "%@%@: %.1f%% CPU", screen, args.isEmpty ? "" : " " + args.joined(separator: " "), percent))
        XCTAssertLessThan(percent, budget, "\(screen) used \(percent)% CPU")
    }

    private func cpuSeconds(_ pid: Int32) throws -> Double {
        let out = try shell("/bin/ps", ["-o", "cputime=", "-p", "\(pid)"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = out.split(whereSeparator: { $0 == ":" || $0 == "." }).compactMap { Double($0) }
        switch parts.count {
        case 4: return parts[0] * 3600 + parts[1] * 60 + parts[2] + parts[3] / 100
        case 3: return parts[0] * 60 + parts[1] + parts[2] / 100
        default: throw NSError(domain: "AppCPUTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "bad cputime: \(out)"])
        }
    }

    private func kill() {
        _ = try? shell("/usr/bin/pkill", ["-f", "MacOS/BetterActivityMonitor"])
        Thread.sleep(forTimeInterval: 1)
    }

    @discardableResult
    private func shell(_ path: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        try p.run()
        p.waitUntilExit()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
}
