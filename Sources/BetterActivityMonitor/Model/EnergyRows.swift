import Foundation
import SystemKit

/// One line of the Energy page: an app with all its helper processes, or a lone process.
struct EnergyGroup: Identifiable, Hashable {
    /// Bundle path, or `pid:<n>` for a process outside any bundle.
    var id: String
    var name: String
    /// The process to reveal or show the icon of: the app itself when it runs, else the hungriest member.
    var leadPID: pid_t
    var pids: [pid_t]
    var power: Double = 0
    var energyTotal: Double = 0
    var wakeups: Double = 0
    /// False when every member belongs to another user; the kernel hides their energy.
    var hasTaskInfo = false
}

enum EnergySort: String, CaseIterable, Identifiable {
    case power, energy, wakeups
    var id: String { rawValue }
    var label: String {
        switch self {
        case .power: "Power"
        case .energy: "Energy Used"
        case .wakeups: "Wake Ups"
        }
    }
}

enum EnergyRows {
    static func groups(_ processes: [ProcessEntry], apps: [pid_t: AppInfo],
                       displayName: (ProcessEntry) -> String) -> [EnergyGroup] {
        var groups: [String: EnergyGroup] = [:]
        var leadPower: [String: Double] = [:]
        for p in processes {
            let bundle = AppBundle.path(forExecutable: p.path)
            let key = bundle ?? "pid:\(p.pid)"
            let isApp = apps[p.pid]?.isRegular == true
            var group = groups[key] ?? EnergyGroup(
                id: key, name: bundle.map(AppBundle.name(ofBundle:)) ?? displayName(p), leadPID: p.pid, pids: [])
            group.pids.append(p.pid)
            group.power += p.power
            group.energyTotal += p.energyTotal
            group.wakeups += p.idleWakeupsPerSecond
            group.hasTaskInfo = group.hasTaskInfo || p.hasTaskInfo
            // The app's main process names and leads the group; otherwise the busiest member does.
            if isApp {
                group.name = apps[p.pid]?.name ?? group.name
                group.leadPID = p.pid
                leadPower[key] = .infinity
            } else if p.power > leadPower[key, default: -1] {
                group.leadPID = p.pid
                leadPower[key] = p.power
            }
            groups[key] = group
        }
        return Array(groups.values)
    }

    static func sorted(_ groups: [EnergyGroup], by sort: EnergySort) -> [EnergyGroup] {
        groups.sorted {
            let (a, b): (Double, Double) = switch sort {
            case .power: ($0.power, $1.power)
            case .energy: ($0.energyTotal, $1.energyTotal)
            case .wakeups: ($0.wakeups, $1.wakeups)
            }
            return a != b ? a > b : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}

extension Fmt {
    static func watts(_ value: Double) -> String {
        if value <= 0 { return "0 W" }
        if value < 0.01 { return String(format: "%.0f mW", value * 1000) }
        return String(format: value < 10 ? "%.2f W" : "%.1f W", value)
    }

    /// Joules, shown as Wh once they add up (1 Wh = 3600 J), which is how battery capacity is quoted.
    static func energy(_ joules: Double) -> String {
        if joules < 3600 { return String(format: "%.0f J", joules) }
        return String(format: joules < 36_000 ? "%.2f Wh" : "%.1f Wh", joules / 3600)
    }
}
