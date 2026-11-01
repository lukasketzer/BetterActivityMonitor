import SwiftUI
import SystemKit

/// Where the power goes: per-app watts from the kernel's energy counters, what keeps the Mac awake,
/// and the drain over time.
struct EnergyView: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.theme) private var theme
    @AppStorage("energy.sort") private var sort: EnergySort = .power
    /// Average watts over the last hour by app, from the on-disk history.
    @State private var hourAverage: [String: Double] = [:]
    @State private var day = HistoryData()
    @State private var dayRange = Date().addingTimeInterval(-86_400)...Date()
    @State private var hover: Date?

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
                        HistoryChart(series: powerSeries, maxY: nil) { Fmt.watts($0) }
                            .frame(height: 140)
                    }

                    Panel("Power by App", symbol: "bolt.fill") {
                        Picker("Sort by", selection: $sort) {
                            ForEach(EnergySort.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    } content: {
                        EnergyTable(groups: Array(groups.prefix(25)), hourAverage: hourAverage)
                    }

                    Panel("Preventing Sleep", symbol: "moon.zzz") {
                        SleepBlockerList(blockers: sleepBlockers(s))
                    }

                    if !day[.power].isEmpty {
                        Panel("Last 24 Hours", symbol: "clock.arrow.circlepath", destination: .history) {
                            VStack(spacing: 4) {
                                TimelineChart(series: [TimelineSeries(name: "Mac", color: theme.mid, values: day[.power])],
                                              range: dayRange, bucket: TimeInterval(HistoryRange.day.bucket),
                                              hover: $hover) { Fmt.watts($0) }
                                    .frame(height: 100)
                                if !day[.battery].isEmpty {
                                    TimelineChart(series: [TimelineSeries(name: "Charge", color: theme.low, values: day[.battery])],
                                                  range: dayRange, bucket: TimeInterval(HistoryRange.day.bucket), maxY: 1,
                                                  hover: $hover) { Fmt.percent($0, digits: 0) }
                                        .frame(height: 60)
                                }
                                TimelineAxis(range: dayRange)
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .task {
            while !Task.isCancelled {
                await loadHistory()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private func loadHistory() async {
        let now = Date()
        let history = store.history
        let hourAgo = now.addingTimeInterval(-3600)
        let lastHour = await history.topProcesses(from: hourAgo, to: now, by: .energy, limit: 200)
        // Over every minute recorded in the hour, so neither a fresh launch nor an app that only
        // sometimes made the top few skews the average.
        let recorded = await history.series(.cpu, from: hourAgo, to: now).count
        let seconds = Double(max(recorded, 1) * 60)
        hourAverage = Dictionary(lastHour.map { ($0.key, $0.energy / seconds) }, uniquingKeysWith: max)
        dayRange = now.addingTimeInterval(-86_400)...now
        var data = HistoryData()
        for metric in [HistoryMetric.power, .battery] {
            data.series[metric] = await history.series(metric, from: dayRange.lowerBound, to: now, bucket: HistoryRange.day.bucket)
        }
        day = data
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
    var hourAverage: [String: Double]

    /// History keys apps by bundle path and lone processes by name.
    private func average(_ group: EnergyGroup) -> Double? {
        hourAverage[group.id.hasPrefix("pid:") ? group.name : group.id]
    }

    var body: some View {
        let top = max(groups.map(\.power).max() ?? 0, 0.001)
        VStack(spacing: 2) {
            HStack {
                Text("App").frame(maxWidth: .infinity, alignment: .leading)
                Text("Power").frame(width: 150, alignment: .trailing)
                Text("Avg 1 h").frame(width: 70, alignment: .trailing)
                    .help("Average power over the last hour, from History")
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
                        Text(average(group).map(Fmt.watts) ?? "—").frame(width: 70, alignment: .trailing)
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
