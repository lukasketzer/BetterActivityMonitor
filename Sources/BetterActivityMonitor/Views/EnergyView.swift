import SwiftUI
import SystemKit

/// Where the power goes: per-app watts from the kernel's energy counters, what keeps the Mac awake,
/// and the drain over time.
struct EnergyView: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.theme) private var theme
    @AppStorage("energy.sort") private var sort: EnergySort = .power
    @AppStorage(SettingsKey.historyEnabled) private var historyEnabled = false
    @AppStorage(SettingsKey.historyRange) private var range: HistoryRange = .live

    private var isLive: Bool { !historyEnabled || range == .live }

    var body: some View {
        DetailPage {
            if let s = store.snapshot {
                let groups = store.energyGroups(sort: sort)
                VStack(alignment: .leading, spacing: 16) {
                    StatStrip {
                        if let power = store.systemPower {
                            BigStat(title: "Mac is using", value: Fmt.watts(power), color: theme.mid)
                        }
                        BigStat(title: "Apps", value: Fmt.watts(store.processPower.last ?? 0))
                        if let b = s.battery {
                            BigStat(title: "Power source", value: b.isPluggedIn ? "Charger" : "Battery")
                            if let minutes = b.minutesRemaining {
                                BigStat(title: b.isCharging ? "Until full" : "Remaining", value: Fmt.minutes(minutes))
                            }
                        }
                        BigStat(title: "Preventing sleep", value: "\(sleepBlockers(s).count)",
                                color: sleepBlockers(s).isEmpty ? .primary : theme.mid)
                    }

                    Panel("Power Over Time", symbol: "chart.xyaxis.line") {
                        HistoryRangePicker()
                    } content: {
                        RangedChart(series: [HistorySeries(metric: .power, name: "Mac", color: theme.mid)],
                                    maxY: nil, format: { Fmt.watts($0) }) {
                            HistoryChart(series: powerSeries, maxY: nil) { Fmt.watts($0) }
                        }
                        .frame(height: 140)
                    }

                    if isLive {
                        Panel("Power by App", symbol: "bolt.fill") {
                            Picker("Sort by", selection: $sort) {
                                ForEach(EnergySort.allCases) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .fixedSize()
                        } content: {
                            EnergyTable(groups: Array(groups.prefix(25)))
                        }
                    } else {
                        Panel("Energy by App · last \(range.rawValue)", symbol: "bolt.fill") {
                            RangedTopList(ranking: .energy, count: 15) { EmptyView() }
                        }
                    }

                    Panel("Preventing Sleep", symbol: "moon.zzz") {
                        SleepBlockerList(blockers: sleepBlockers(s))
                    }
                }
                .padding()
            }
        }
    }

    /// The battery's view of total draw when it has one, plus what the processes account for.
    private var powerSeries: [ChartSeries] {
        var series = [ChartSeries(name: "Apps", color: theme.cpu, history: store.processPower)]
        if store.batteryPower.points.count > 1 {
            series.insert(ChartSeries(name: "Battery", color: theme.mid, history: store.batteryPower), at: 0)
        }
        return series
    }

    private func sleepBlockers(_ s: SystemSnapshot) -> [(pid: pid_t, assertions: [PowerAssertion])] {
        s.powerAssertions
            .map { (pid: $0.key, assertions: $0.value.filter(\.preventsSleep)) }
            .filter { !$0.assertions.isEmpty }
            .sorted { $0.pid < $1.pid }
    }
}

private struct EnergyTable: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.theme) private var theme
    var groups: [EnergyGroup]

    var body: some View {
        let top = max(groups.map(\.power).max() ?? 0, 0.001)
        VStack(spacing: 2) {
            HStack {
                Text("App").frame(maxWidth: .infinity, alignment: .leading)
                Text("Power").frame(width: 150, alignment: .trailing)
                Text("Energy Used").frame(width: 90, alignment: .trailing)
                Text("Wake Ups").frame(width: 80, alignment: .trailing)
                Text("Processes").frame(width: 70, alignment: .trailing)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)

            ForEach(groups) { group in
                Button {
                    store.reveal(group.leadPID)
                } label: {
                    HStack {
                        HStack(spacing: 6) {
                            icon(group)
                            Text(group.name).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 6) {
                            MeterBar(fraction: group.power / top, color: theme.meter(group.power / top))
                                .frame(width: 60, height: 6)
                            Text(group.hasTaskInfo ? Fmt.watts(group.power) : "—")
                                .frame(width: 70, alignment: .trailing)
                        }
                        .frame(width: 150, alignment: .trailing)
                        Text(group.hasTaskInfo ? Fmt.energy(group.energyTotal) : "—").frame(width: 90, alignment: .trailing)
                        Text(group.hasTaskInfo ? Fmt.compact(group.wakeups) : "—").frame(width: 80, alignment: .trailing)
                        Text("\(group.pids.count)").frame(width: 70, alignment: .trailing)
                    }
                    .font(.callout.monospacedDigit())
                    .padding(.vertical, 3)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(HoverRowStyle())
                .help("Show \(group.name) (PID \(group.leadPID))")
            }
        }
    }

    @ViewBuilder
    private func icon(_ group: EnergyGroup) -> some View {
        if let entry = store.process(group.leadPID),
           let image = store.apps[group.leadPID]?.icon ?? store.icon(for: ProcessRow.build(
               from: entry, app: nil, totalMemory: 0, cpuDivisor: 1)) {
            Image(nsImage: image).resizable().frame(width: 16, height: 16)
        } else {
            Image(systemName: "terminal").font(.caption).frame(width: 16).foregroundStyle(.tertiary)
        }
    }
}

private struct SleepBlockerList: View {
    @Environment(SystemStore.self) private var store
    var blockers: [(pid: pid_t, assertions: [PowerAssertion])]

    var body: some View {
        if blockers.isEmpty {
            Text("Nothing is keeping your Mac awake.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(spacing: 8) {
                ForEach(blockers, id: \.pid) { blocker in
                    let name = store.process(blocker.pid).map(store.displayName) ?? "PID \(blocker.pid)"
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name).font(.callout.weight(.medium))
                            ForEach(Array(blocker.assertions.enumerated()), id: \.offset) { _, assertion in
                                Text(describe(assertion)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        Spacer()
                        Button("Show") { store.reveal(blocker.pid) }
                        Button("Quit") { store.requestQuit([blocker.pid]) }
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private func describe(_ a: PowerAssertion) -> String {
        var text = a.effect
        if !a.name.isEmpty { text += ": \(a.name)" }
        if let created = a.created { text += " · for \(Fmt.duration(Date().timeIntervalSince(created)))" }
        return text
    }
}
