import Foundation
import SystemKit

// Measures each sampler's cost: `swift run -c release sysbench [iterations]`.
let iterations = Int(CommandLine.arguments.dropFirst().first ?? "") ?? 20
let monitor = SystemMonitor()
_ = await monitor.sample()

var totals: [String: [Double]] = [:]
var order: [String] = []
let cpuStart = clock()
for _ in 0..<iterations {
    try await Task.sleep(for: .milliseconds(250))
    _ = await monitor.sample()
    for (name, ms) in await monitor.lastTimings {
        if totals[name] == nil { order.append(name) }
        totals[name, default: []].append(ms)
    }
}
let cpuSeconds = Double(clock() - cpuStart) / Double(CLOCKS_PER_SEC)

print("sampler        median ms     max ms")
var sum = 0.0
for name in order {
    let v = totals[name]!.sorted()
    let median = v[v.count / 2]
    sum += median
    print(name.padding(toLength: 14, withPad: " ", startingAt: 0), String(format: "%9.2f  %9.2f", median, v.last!))
}
for name in order {
    let fired = totals[name]!.filter { $0 > 0.01 }
    if fired.count < totals[name]!.count, !fired.isEmpty {
        print("  \(name) when active: \(fired.map { String(format: "%.1f", $0) }.joined(separator: ", ")) ms")
    }
}
print(String(format: "total median per tick: %.2f ms", sum))
print(String(format: "process CPU time: %.0f ms over %d ticks = %.2f ms/tick", cpuSeconds * 1000, iterations, cpuSeconds * 1000 / Double(iterations)))
