import Foundation
import IOKit

final class GPUSampler {
    private var service: io_object_t = 0
    private var name = "GPU"
    private var coreCount: Int?
    private var lookedUp = false

    deinit { if service != 0 { IOObjectRelease(service) } }

    func sample() -> GPUStats? {
        if !lookedUp { lookUp() }
        // Fetching the full registry entry costs ~2 ms; the single statistics property is far cheaper.
        guard service != 0,
              let perf = IORegistry.property("PerformanceStatistics", of: service) as? [String: Any] else { return nil }
        let utilization = perf.number("Device Utilization %") ?? perf.number("GPU Activity(%)") ?? 0
        return GPUStats(
            name: name,
            coreCount: coreCount,
            utilization: utilization / 100,
            rendererUtilization: perf.number("Renderer Utilization %").map { $0 / 100 },
            tilerUtilization: perf.number("Tiler Utilization %").map { $0 / 100 },
            memoryUsed: perf.uint64("In use system memory") ?? perf.uint64("vramUsedBytes"),
            memoryAllocated: perf.uint64("Alloc system memory")
        )
    }

    private func lookUp() {
        lookedUp = true
        var bestUtilization = -1.0
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        while case let candidate = IOIteratorNext(iterator), candidate != 0 {
            let perf = IORegistry.property("PerformanceStatistics", of: candidate) as? [String: Any]
            let utilization = perf?.number("Device Utilization %") ?? -0.5
            // Prefer the busiest GPU when several are present (e.g. integrated + discrete).
            if perf != nil, utilization > bestUtilization {
                if service != 0 { IOObjectRelease(service) }
                service = candidate
                bestUtilization = utilization
                name = (IORegistry.property("model", of: candidate) as? String)
                    ?? (IORegistry.property("model", of: candidate) as? Data).flatMap { String(data: $0, encoding: .utf8) }
                    ?? "GPU"
                name = name.trimmingCharacters(in: .controlCharacters)
                coreCount = (IORegistry.property("gpu-core-count", of: candidate) as? NSNumber)?.intValue
            } else {
                IOObjectRelease(candidate)
            }
        }
    }
}
