import Darwin
import Foundation

final class ProcessSampler {
    private struct Previous {
        var startTime: Date
        var cpuNanos: UInt64
        var diskRead: UInt64
        var diskWrite: UInt64
        var wakeups: UInt64
        var energyNJ: UInt64
        /// From the last task-info read; reused while the process stays idle (see `taskInfoRefresh`).
        var threads: Int
        var resident: UInt64
        var taskInfoTick: Int
    }

    /// Task info (thread count, running state) costs a second syscall per process and was a third of the
    /// sampler's kernel time. A process that used no CPU since the last tick cannot have started or ended
    /// threads or been running, so its last answer is reused, refreshed at least this many ticks apart.
    private static let taskInfoRefresh = 10
    private var tick = 0
    private var kinfoBuffer: [kinfo_proc] = []

    /// v6 adds `ri_energy_nj`. It extends v4 field for field, so a v4 answer fills the same struct
    /// (energy then stays 0). Starts at v6 and drops to v4 for good if the kernel refuses it.
    private var rusageFlavor = Int32(RUSAGE_INFO_V6)

    private var previous: [pid_t: Previous] = [:]
    private var previousTime: Date?
    private var userNames: [uid_t: String] = [:]
    private var paths: [pid_t: (start: Date, path: String)] = [:]
    /// Processes whose task info the kernel refused (other users); retrying every tick wastes ~2 syscalls each.
    private var denied: [pid_t: Date] = [:]

    private(set) var totalThreads = 0

    private static func rusage(_ pid: pid_t, flavor: Int32, into usage: inout rusage_info_v6) -> Bool {
        withUnsafeMutablePointer(to: &usage) { ptr in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, flavor, $0) == 0 }
        }
    }

    func sample() -> [ProcessEntry] {
        let now = Date()
        let dt = previousTime.map { max(now.timeIntervalSince($0), 0.001) }
        tick += 1
        let kinfos = Self.listKinfo(reusing: &kinfoBuffer)
        var result: [ProcessEntry] = []
        result.reserveCapacity(kinfos.count)
        var next: [pid_t: Previous] = [:]
        var threads = 0

        for kp in kinfos {
            let pid = kp.kp_proc.p_pid
            let start = Date(timeIntervalSince1970: TimeInterval(kp.kp_proc.p_un.__p_starttime.tv_sec)
                             + TimeInterval(kp.kp_proc.p_un.__p_starttime.tv_usec) / 1_000_000)
            let uid = kp.kp_eproc.e_ucred.cr_uid
            let comm = String(cTuple: kp.kp_proc.p_comm)
            let path = path(for: pid, start: start)

            var entry = ProcessEntry(
                pid: pid, ppid: kp.kp_eproc.e_ppid, uid: uid, user: userName(uid),
                name: path.isEmpty ? comm : (path as NSString).lastPathComponent,
                path: path, state: .unknown, nice: Int(kp.kp_proc.p_nice), startTime: start,
                hasTaskInfo: false, cpu: 0, cpuTime: 0, memory: 0, resident: 0, threads: 0,
                diskReadRate: 0, diskWriteRate: 0, diskReadTotal: 0, diskWriteTotal: 0,
                idleWakeupsPerSecond: 0
            )
            if entry.name.isEmpty { entry.name = pid == 0 ? "kernel_task" : "(\(pid))" }

            switch Int32(kp.kp_proc.p_stat) {
            case SZOMB: entry.state = .zombie
            case SSTOP: entry.state = .stopped
            case SIDL: entry.state = .idle
            default: break
            }

            if denied[pid] == start {
                result.append(entry)
                continue
            }

            var usage = rusage_info_v6()
            var usageOK = Self.rusage(pid, flavor: rusageFlavor, into: &usage)
            if !usageOK, rusageFlavor == RUSAGE_INFO_V6, errno == EINVAL {
                rusageFlavor = Int32(RUSAGE_INFO_V4)
                usageOK = Self.rusage(pid, flavor: rusageFlavor, into: &usage)
            }
            if usageOK {
                entry.hasTaskInfo = true
                let cpuNanos = UInt64(Double(usage.ri_user_time + usage.ri_system_time) * MachTime.nanosPerTick)
                entry.cpuTime = Double(cpuNanos) / 1e9
                entry.memory = usage.ri_phys_footprint
                entry.resident = usage.ri_resident_size
                entry.diskReadTotal = usage.ri_diskio_bytesread
                entry.diskWriteTotal = usage.ri_diskio_byteswritten
                let wakeups = usage.ri_pkg_idle_wkups + usage.ri_interrupt_wkups
                entry.energyTotal = Double(usage.ri_energy_nj) / 1e9

                let prev = previous[pid].flatMap { $0.startTime == start ? $0 : nil }
                if let dt, let prev {
                    entry.cpu = Double(cpuNanos &- prev.cpuNanos) / (dt * 1e9) * 100
                    entry.diskReadRate = Double(entry.diskReadTotal &- prev.diskRead) / dt
                    entry.diskWriteRate = Double(entry.diskWriteTotal &- prev.diskWrite) / dt
                    entry.idleWakeupsPerSecond = Double(wakeups &- prev.wakeups) / dt
                    if usage.ri_energy_nj >= prev.energyNJ {
                        entry.power = Double(usage.ri_energy_nj - prev.energyNJ) / (dt * 1e9)
                    }
                    if entry.cpu < 0 || entry.cpu > 100_000 { entry.cpu = 0 }
                }
                var info = Previous(startTime: start, cpuNanos: cpuNanos,
                                    diskRead: entry.diskReadTotal, diskWrite: entry.diskWriteTotal,
                                    wakeups: wakeups, energyNJ: usage.ri_energy_nj,
                                    threads: 0, resident: 0, taskInfoTick: -Self.taskInfoRefresh)
                if let prev, prev.cpuNanos == cpuNanos, tick - prev.taskInfoTick < Self.taskInfoRefresh {
                    info.threads = prev.threads
                    info.resident = prev.resident
                    info.taskInfoTick = prev.taskInfoTick
                    entry.threads = prev.threads
                    if entry.resident == 0 { entry.resident = prev.resident }
                    if entry.state == .unknown { entry.state = .sleeping }
                } else if let task = Self.taskInfo(pid) {
                    info.threads = Int(task.pti_threadnum)
                    info.resident = task.pti_resident_size
                    info.taskInfoTick = tick
                    Self.apply(task, to: &entry)
                }
                next[pid] = info
            } else if let task = Self.taskInfo(pid) {
                Self.apply(task, to: &entry)
            }
            if !entry.hasTaskInfo { denied[pid] = start }
            threads += entry.threads
            result.append(entry)
        }

        previous = next
        previousTime = now
        totalThreads = threads
        let alive = Set(result.map(\.pid))
        paths = paths.filter { alive.contains($0.key) }
        denied = denied.filter { alive.contains($0.key) }
        return result
    }

    private static func taskInfo(_ pid: pid_t) -> proc_taskinfo? {
        var task = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, size) == size ? task : nil
    }

    private static func apply(_ task: proc_taskinfo, to entry: inout ProcessEntry) {
        entry.hasTaskInfo = true
        entry.threads = Int(task.pti_threadnum)
        if entry.resident == 0 { entry.resident = task.pti_resident_size }
        if entry.state == .unknown { entry.state = task.pti_numrunning > 0 ? .running : .sleeping }
    }

    private func path(for pid: pid_t, start: Date) -> String {
        if let cached = paths[pid], cached.start == start { return cached.path }
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let len = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        let path = len > 0 ? String(cString: buffer) : ""
        paths[pid] = (start, path)
        return path
    }

    private func userName(_ uid: uid_t) -> String {
        if let name = userNames[uid] { return name }
        let name = getpwuid(uid).map { String(cString: $0.pointee.pw_name) } ?? String(uid)
        userNames[uid] = name
        return name
    }

    /// Lists every process into `buffer`, which is kept between calls so the ~700 KB table isn't
    /// reallocated and zeroed every tick; it only grows when the process count outgrows it.
    static func listKinfo(reusing buffer: inout [kinfo_proc]) -> ArraySlice<kinfo_proc> {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        let stride = MemoryLayout<kinfo_proc>.stride
        for attempt in 0..<4 {
            if attempt > 0 || buffer.isEmpty {
                var needed = 0
                guard sysctl(&mib, 4, nil, &needed, nil, 0) == 0 else { return [] }
                needed += needed / 8
                if needed / stride > buffer.count { buffer = [kinfo_proc](repeating: kinfo_proc(), count: needed / stride) }
            }
            var size = buffer.count * stride
            if sysctl(&mib, 4, &buffer, &size, nil, 0) == 0 {
                return buffer[..<(size / stride)]
            }
            if errno != ENOMEM { return [] }
        }
        return []
    }
}
