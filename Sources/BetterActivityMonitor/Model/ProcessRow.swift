import AppKit
import SystemKit

enum ProcessScope: String, CaseIterable, Identifiable {
    case all, mine, apps, system, active
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: "All Processes"
        case .mine: "My Processes"
        case .apps: "Apps"
        case .system: "System Processes"
        case .active: "Active Processes"
        }
    }
}

/// Flat table row; tree mode encodes hierarchy through `depth` and `hasChildren`.
struct ProcessRow: Identifiable, Hashable {
    var id: pid_t { pid }
    var pid: pid_t
    var ppid: pid_t
    var name: String
    var user: String
    var uid: uid_t
    var path: String
    var state: ProcessState
    var nice: Int
    var startTime: Date
    var hasTaskInfo: Bool
    var cpu: Double
    var cpuTime: TimeInterval
    var memory: UInt64
    var memoryFraction: Double
    var resident: UInt64
    var threads: Int
    var diskReadRate: Double
    var diskWriteRate: Double
    var diskReadTotal: UInt64
    var diskWriteTotal: UInt64
    var wakeups: Double
    var isApp: Bool
    var depth = 0
    var hasChildren = false
    var isCollapsed = false
    /// In tree mode a collapsed parent shows the sum of its subtree, like btop.
    var subtreeCPU: Double = 0
    var subtreeMemory: UInt64 = 0

    static func build(from entry: ProcessEntry, app: AppInfo?, totalMemory: UInt64, cpuDivisor: Double) -> ProcessRow {
        ProcessRow(
            pid: entry.pid, ppid: entry.ppid, name: app?.name ?? entry.name, user: entry.user, uid: entry.uid,
            path: entry.path, state: entry.state, nice: entry.nice, startTime: entry.startTime,
            hasTaskInfo: entry.hasTaskInfo, cpu: entry.cpu / cpuDivisor, cpuTime: entry.cpuTime,
            memory: entry.memory,
            memoryFraction: totalMemory == 0 ? 0 : Double(entry.memory) / Double(totalMemory),
            resident: entry.resident, threads: entry.threads,
            diskReadRate: entry.diskReadRate, diskWriteRate: entry.diskWriteRate,
            diskReadTotal: entry.diskReadTotal, diskWriteTotal: entry.diskWriteTotal,
            wakeups: entry.idleWakeupsPerSecond, isApp: app?.isRegular ?? false
        )
    }
}

struct AppInfo {
    var name: String
    var icon: NSImage?
    var bundleIdentifier: String?
    var isRegular: Bool
}

enum ProcessRowBuilder {
    static func matches(_ row: ProcessRow, query: String, regex: Regex<AnyRegexOutput>?) -> Bool {
        if query.isEmpty { return true }
        if let regex {
            return row.name.contains(regex) || row.path.contains(regex) || row.user.contains(regex) || String(row.pid).contains(regex)
        }
        return row.name.localizedCaseInsensitiveContains(query) || row.path.localizedCaseInsensitiveContains(query)
            || row.user.localizedCaseInsensitiveContains(query) || String(row.pid) == query
    }

    static func inScope(_ row: ProcessRow, scope: ProcessScope, myUID: uid_t) -> Bool {
        switch scope {
        case .all: true
        case .mine: row.uid == myUID
        case .apps: row.isApp
        case .system: row.uid != myUID
        case .active: row.cpu >= 0.1 || row.diskReadRate + row.diskWriteRate > 0
        }
    }

    /// Flat or tree-ordered rows. In tree mode filtering keeps the ancestors of every match.
    static func rows(_ all: [ProcessRow], matching keep: (ProcessRow) -> Bool, sort: [KeyPathComparator<ProcessRow>],
                     tree: Bool, collapsed: Set<pid_t>) -> [ProcessRow] {
        guard tree else { return all.filter(keep).sorted(using: sort) }

        let byPID = Dictionary(all.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        var children: [pid_t: [ProcessRow]] = [:]
        var roots: [ProcessRow] = []
        for row in all {
            if row.ppid != row.pid, byPID[row.ppid] != nil { children[row.ppid, default: []].append(row) } else { roots.append(row) }
        }

        var visible = Set<pid_t>()
        for row in all where keep(row) {
            var current: ProcessRow? = row
            while let c = current, visible.insert(c.pid).inserted {
                current = c.ppid != c.pid ? byPID[c.ppid] : nil
            }
        }

        func totals(_ row: ProcessRow) -> (Double, UInt64) {
            (children[row.pid] ?? []).reduce((row.cpu, row.memory)) { acc, child in
                let t = totals(child)
                return (acc.0 + t.0, acc.1 + t.1)
            }
        }

        var result: [ProcessRow] = []
        func walk(_ rows: [ProcessRow], depth: Int) {
            for var row in rows.filter({ visible.contains($0.pid) }).sorted(using: sort) {
                let kids = children[row.pid] ?? []
                row.depth = depth
                row.hasChildren = kids.contains { visible.contains($0.pid) }
                row.isCollapsed = collapsed.contains(row.pid)
                if row.isCollapsed { (row.subtreeCPU, row.subtreeMemory) = totals(row) }
                result.append(row)
                if row.hasChildren && !row.isCollapsed { walk(kids, depth: depth + 1) }
            }
        }
        walk(roots, depth: 0)
        return result
    }
}
