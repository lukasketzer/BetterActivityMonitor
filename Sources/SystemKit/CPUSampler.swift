import Darwin
import Foundation

final class CPUSampler {
    private struct Ticks { var user, system, idle, nice: UInt32 }  // wrap-safe deltas via &-

    private var previous: [Ticks] = []
    private let model: String
    private let physicalCores: Int
    private let logicalCores: Int
    private let performanceCores: Int
    private let efficiencyCores: Int
    private let bootTime: Date

    init() {
        model = Sysctl.string("machdep.cpu.brand_string") ?? "Unknown CPU"
        physicalCores = Sysctl.int("hw.physicalcpu") ?? 0
        logicalCores = Sysctl.int("hw.logicalcpu") ?? 0
        // On Apple Silicon perflevel0 is the performance cluster, perflevel1 efficiency.
        let levels = Sysctl.int("hw.nperflevels") ?? 1
        if levels > 1 {
            performanceCores = Sysctl.int("hw.perflevel0.logicalcpu") ?? 0
            efficiencyCores = Sysctl.int("hw.perflevel1.logicalcpu") ?? 0
        } else {
            performanceCores = 0
            efficiencyCores = 0
        }
        let boot = Sysctl.value("kern.boottime", as: timeval.self, initial: timeval())
        bootTime = boot.map { Date(timeIntervalSince1970: TimeInterval($0.tv_sec)) } ?? Date()
    }

    func sample(processCount: Int, threadCount: Int) -> CPUStats {
        let ticks = readTicks()
        var cores: [CoreLoad] = []
        var sumUser = 0.0, sumSystem = 0.0
        for (i, now) in ticks.enumerated() {
            let prev = i < previous.count ? previous[i] : Ticks(user: 0, system: 0, idle: 0, nice: 0)
            let user = Double(now.user &- prev.user) + Double(now.nice &- prev.nice)
            let system = Double(now.system &- prev.system)
            let idle = Double(now.idle &- prev.idle)
            let total = user + system + idle
            let load = total > 0 ? CoreLoad(user: user / total, system: system / total) : CoreLoad(user: 0, system: 0)
            cores.append(load)
            sumUser += load.user
            sumSystem += load.system
        }
        previous = ticks

        var kinds = [CoreKind](repeating: .standard, count: cores.count)
        if efficiencyCores > 0, efficiencyCores <= cores.count {
            // Efficiency cores are enumerated first on Apple Silicon.
            for i in kinds.indices { kinds[i] = i < efficiencyCores ? .efficiency : .performance }
        }

        var loads = [Double](repeating: 0, count: 3)
        getloadavg(&loads, 3)

        let n = Double(max(cores.count, 1))
        return CPUStats(
            user: sumUser / n,
            system: sumSystem / n,
            cores: cores,
            coreKinds: kinds,
            loadAverage: loads,
            uptime: Date().timeIntervalSince(bootTime),
            model: model,
            physicalCores: physicalCores,
            logicalCores: logicalCores,
            performanceCores: performanceCores,
            efficiencyCores: efficiencyCores,
            processCount: processCount,
            threadCount: threadCount
        )
    }

    private func readTicks() -> [Ticks] {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return [] }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        let stride = Int(CPU_STATE_MAX)
        return (0..<Int(count)).map { i in
            func t(_ state: Int32) -> UInt32 { UInt32(bitPattern: info[i * stride + Int(state)]) }
            return Ticks(user: t(CPU_STATE_USER), system: t(CPU_STATE_SYSTEM),
                         idle: t(CPU_STATE_IDLE), nice: t(CPU_STATE_NICE))
        }
    }
}
