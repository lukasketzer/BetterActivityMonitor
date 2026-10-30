import Darwin
import Foundation
import SystemKit

/// Compares one `nettop -L 1` spawn per tick against a single long-lived `nettop -L 0` stream.
/// CPU comes from RUSAGE_CHILDREN, so it counts nettop's own time, which `clock()` would miss.
enum NettopBench {
    static func run(seconds: Double) {
        let ticks = max(Int(seconds), 1)
        print("nettop CPU over \(ticks) one-second ticks")

        let spawn = childCPU {
            for _ in 0..<ticks {
                let start = Date()
                let process = launch(["-L", "1", "-n", "-x"])
                _ = (process.standardOutput as? Pipe)?.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                Thread.sleep(forTimeInterval: max(1 - Date().timeIntervalSince(start), 0))
            }
        }
        report("spawn -L 1 per tick", spawn, ticks)

        let stream = childCPU {
            let process = launch(["-L", "0", "-n", "-x", "-s", "1"], toPipe: false)
            Thread.sleep(forTimeInterval: Double(ticks))
            process.terminate()
            process.waitUntilExit()
        }
        report("stream -L 0 -s 1", stream, ticks)
    }

    /// Full `SystemMonitor.sample()` cost per connection mode: our own CPU plus nettop's.
    static func runModes(ticks: Int) async {
        print("SystemMonitor CPU per tick (own + nettop) over \(ticks) ticks")
        for (name, mode) in [("off", ConnectionMode.off), ("external", .external), ("all", .all)] {
            let monitor = SystemMonitor()
            await monitor.setConnectionMode(mode)
            _ = await monitor.sample()
            let ownStart = clock()
            var spent = 0.0
            var flows = 0
            for _ in 0..<ticks {
                // The default refresh interval; faster ones reuse nettop results (ConnectionSampler.minimumInterval).
                try? await Task.sleep(for: .seconds(1))
                var snapshot: SystemSnapshot?
                spent += await childCPUAsync { snapshot = await monitor.sample() }
                flows = snapshot?.connections?.flows.count ?? 0
            }
            let own = Double(clock() - ownStart) / Double(CLOCKS_PER_SEC)
            print(name.padding(toLength: 10, withPad: " ", startingAt: 0),
                  String(format: "own %6.1f ms  nettop %6.1f ms  total %6.1f ms/tick  (%d flows)",
                         own * 1000 / Double(ticks), spent * 1000 / Double(ticks),
                         (own + spent) * 1000 / Double(ticks), flows))
        }
    }

    private static func childCPUAsync(_ body: () async -> Void) async -> Double {
        let before = childSeconds()
        await body()
        return childSeconds() - before
    }

    private static func childSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_CHILDREN, &usage)
        func s(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1e6 }
        return s(usage.ru_utime) + s(usage.ru_stime)
    }

    /// `toPipe: false` writes to /dev/null: a pipe drained by a readabilityHandler once stalled the
    /// stream and reported 1.6% instead of the ~146% that `/usr/bin/time` measures repeatedly.
    private static func launch(_ arguments: [String], toPipe: Bool = true) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = arguments
        process.standardOutput = toPipe ? Pipe() : FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        return process
    }

    private static func childCPU(_ body: () -> Void) -> Double {
        let before = childSeconds()
        body()
        return childSeconds() - before
    }

    private static func report(_ name: String, _ cpu: Double, _ ticks: Int) {
        print(name.padding(toLength: 22, withPad: " ", startingAt: 0),
              String(format: "%7.0f ms total  %6.1f ms/tick  %5.1f%% of one core", cpu * 1000, cpu * 1000 / Double(ticks), cpu / Double(ticks) * 100))
    }
}
