import Foundation
import IOKit

/// Per-process GPU time from the GPU driver's user clients.
///
/// Every process that opens the GPU gets a user client (`AGXDeviceUserClient` on Apple Silicon) under the
/// `IOAccelerator` service. It carries `IOUserClientCreator` ("pid 412, WindowServer") and `AppUsage`, a list
/// of command queues each with `accumulatedGPUTime` in nanoseconds. A process can own several clients.
final class ProcessGPUSampler {
    struct Usage {
        /// Fraction of the GPU's time over the last tick (0...1, can exceed 1 with parallel queues).
        var utilization: Double
        /// GPU time used by the process's currently open clients.
        var gpuTime: TimeInterval
    }

    private var previous: [pid_t: UInt64] = [:]
    private var lastSample: UInt64?

    /// Forgets the last counters so a later sample doesn't report a gap as usage.
    func reset() {
        previous = [:]
        lastSample = nil
    }

    func sample() -> [pid_t: Usage] {
        let now = DispatchTime.now().uptimeNanoseconds
        var totals: [pid_t: UInt64] = [:]

        var accelerators: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &accelerators) == KERN_SUCCESS
        else { return [:] }
        defer { IOObjectRelease(accelerators) }
        while case let accelerator = IOIteratorNext(accelerators), accelerator != 0 {
            defer { IOObjectRelease(accelerator) }
            var children: io_iterator_t = 0
            guard IORegistryEntryGetChildIterator(accelerator, kIOServicePlane, &children) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(children) }
            while case let client = IOIteratorNext(children), client != 0 {
                defer { IOObjectRelease(client) }
                guard let usage = IORegistry.property("AppUsage", of: client) as? [[String: Any]], !usage.isEmpty,
                      let creator = IORegistry.property("IOUserClientCreator", of: client) as? String,
                      let pid = Self.pid(fromCreator: creator) else { continue }
                let ns = usage.reduce(UInt64(0)) { $0 &+ ($1.uint64("accumulatedGPUTime") ?? 0) }
                totals[pid, default: 0] &+= ns
            }
        }

        let elapsed = lastSample.map { now > $0 ? Double(now - $0) : 0 } ?? 0
        var result: [pid_t: Usage] = [:]
        for (pid, ns) in totals {
            var utilization = 0.0
            // A closed client drops its time from the total; treat a shrinking counter as idle.
            if elapsed > 0, let before = previous[pid], ns > before {
                utilization = Double(ns - before) / elapsed
            }
            result[pid] = Usage(utilization: utilization, gpuTime: Double(ns) / 1e9)
        }
        previous = totals
        lastSample = now
        return result
    }

    /// "pid 412, WindowServer" → 412
    static func pid(fromCreator creator: String) -> pid_t? {
        guard creator.hasPrefix("pid ") else { return nil }
        let digits = creator.dropFirst(4).prefix { $0.isNumber }
        return pid_t(digits)
    }
}
