import Darwin
import Foundation

/// Per-flow and per-process traffic from `nettop`, which works without root and sees every process.
/// One short `nettop -L 1` run per tick: its streaming mode (`-L 0`) busy-polls at ~146% of a core.
/// A run costs 20–45 ms CPU (`sysbench nettop`), so faster refresh rates reuse the last result.
final class ConnectionSampler {
    var mode: ConnectionMode = .off {
        didSet { if mode != oldValue { reset() } }
    }
    var minimumInterval: TimeInterval = 0.95

    private var previousFlows: [String: (bytesIn: UInt64, bytesOut: UInt64)] = [:]
    private var previousProcesses: [pid_t: (bytesIn: UInt64, bytesOut: UInt64)] = [:]
    private var firstSeen: [String: Date] = [:]
    private var previousTime: Date?
    private var last: ConnectionStats?

    func sample(now: Date) -> ConnectionStats? {
        guard mode != .off else { return nil }
        if let last, let previousTime, now.timeIntervalSince(previousTime) < minimumInterval { return last }
        let stats = measure(now: now)
        last = stats
        return stats
    }

    private func measure(now: Date) -> ConnectionStats? {
        guard let output = Self.runNettop(mode) else { return nil }
        let parsed = NettopParser.parse(output)
        let dt = previousTime.map { max(now.timeIntervalSince($0), 0.001) }
        previousTime = now

        func rate(_ current: UInt64, _ previous: UInt64?) -> Double {
            guard let dt, let previous, current >= previous else { return 0 }
            return Double(current - previous) / dt
        }

        // A process can hold several sockets with identical endpoints (typically unbound UDP);
        // number repeats so each keeps a stable id across ticks.
        var seen: [String: Int] = [:]
        var flowCounters: [String: (UInt64, UInt64)] = [:]
        var seenAt: [String: Date] = [:]
        let flows = parsed.flows.map { raw -> NetworkFlow in
            let base = "\(raw.pid) \(raw.proto)\(raw.isIPv6 ? "6" : "4") \(raw.local.description) \(raw.remote.description)"
            let index = seen[base, default: 0]
            seen[base] = index + 1
            let id = index == 0 ? base : "\(base) #\(index)"
            let previous = previousFlows[id]
            flowCounters[id] = (raw.bytesIn, raw.bytesOut)
            let first = firstSeen[id] ?? now
            seenAt[id] = first
            return NetworkFlow(
                id: id, pid: raw.pid, processName: raw.processName, proto: raw.proto, isIPv6: raw.isIPv6,
                local: raw.local, remote: raw.remote, interface: raw.interface, state: raw.state,
                bytesIn: raw.bytesIn, bytesOut: raw.bytesOut,
                rateIn: rate(raw.bytesIn, previous?.bytesIn), rateOut: rate(raw.bytesOut, previous?.bytesOut),
                retransmits: raw.retransmits, rtt: raw.rtt, firstSeen: first
            )
        }
        previousFlows = flowCounters.mapValues { (bytesIn: $0.0, bytesOut: $0.1) }
        firstSeen = seenAt

        var processCounters: [pid_t: (bytesIn: UInt64, bytesOut: UInt64)] = [:]
        let processes = parsed.processes.map { raw -> ProcessNetUsage in
            let previous = previousProcesses[raw.pid]
            processCounters[raw.pid] = (raw.bytesIn, raw.bytesOut)
            return ProcessNetUsage(pid: raw.pid, name: raw.name, bytesIn: raw.bytesIn, bytesOut: raw.bytesOut,
                                   rateIn: rate(raw.bytesIn, previous?.bytesIn), rateOut: rate(raw.bytesOut, previous?.bytesOut))
        }
        previousProcesses = processCounters
        return ConnectionStats(mode: mode, flows: flows, processes: processes)
    }

    private func reset() {
        previousFlows = [:]
        previousProcesses = [:]
        firstSeen = [:]
        previousTime = nil
        last = nil
    }

    static func arguments(for mode: ConnectionMode) -> [String] {
        let base = ["-L", "1", "-n", "-x"]
        switch mode {
        case .processes: return ["-P"] + base
        case .external: return base + ["-t", "wifi", "-t", "wired"]
        case .off, .all: return base
        }
    }

    private static func runNettop(_ mode: ConnectionMode) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = arguments(for: mode)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        // A single run finishes in tens of milliseconds; never let a stuck one stall sampling.
        let watchdog = DispatchWorkItem { [weak process] in process?.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 2, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
