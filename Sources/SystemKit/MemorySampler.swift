import Darwin
import Foundation

final class MemorySampler {
    private let total = UInt64(Sysctl.int("hw.memsize") ?? 0)
    private let pageSize = UInt64(vm_kernel_page_size)
    private var previous: vm_statistics64?
    private var previousTime: Date?

    func sample() -> MemoryStats {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let now = Date()
        let swap = Sysctl.value("vm.swapusage", as: xsw_usage.self, initial: xsw_usage())
        let pressureLevel = Sysctl.int("kern.memorystatus_vm_pressure_level") ?? 1

        guard kr == KERN_SUCCESS else {
            return MemoryStats(total: total, app: 0, wired: 0, compressed: 0, cached: 0, free: total,
                               swapTotal: 0, swapUsed: 0, pressure: .normal, pageIns: 0, pageOuts: 0,
                               pageInsPerSecond: 0, pageOutsPerSecond: 0, compressionsPerSecond: 0)
        }

        // Same breakdown Activity Monitor uses.
        let p = pageSize
        let internalPages = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        let app = (internalPages > purgeable ? internalPages - purgeable : 0) * p
        let wired = UInt64(stats.wire_count) * p
        let compressed = UInt64(stats.compressor_page_count) * p
        let cached = (UInt64(stats.external_page_count) + purgeable) * p
        let used = app + wired + compressed
        let free = total > used + cached ? total - used - cached : UInt64(stats.free_count) * p

        var pageInRate = 0.0, pageOutRate = 0.0, compressRate = 0.0
        if let prev = previous, let prevTime = previousTime {
            let dt = max(now.timeIntervalSince(prevTime), 0.001)
            pageInRate = Double(stats.pageins &- prev.pageins) / dt
            pageOutRate = Double(stats.pageouts &- prev.pageouts) / dt
            compressRate = Double(stats.compressions &- prev.compressions) / dt
        }
        previous = stats
        previousTime = now

        return MemoryStats(
            total: total, app: app, wired: wired, compressed: compressed, cached: cached, free: free,
            swapTotal: swap.map { UInt64($0.xsu_total) } ?? 0,
            swapUsed: swap.map { UInt64($0.xsu_used) } ?? 0,
            pressure: MemoryPressure(rawValue: pressureLevel) ?? .normal,
            pageIns: UInt64(stats.pageins), pageOuts: UInt64(stats.pageouts),
            pageInsPerSecond: pageInRate, pageOutsPerSecond: pageOutRate,
            compressionsPerSecond: compressRate
        )
    }
}
