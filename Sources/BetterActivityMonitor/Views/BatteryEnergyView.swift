import SwiftUI
import SystemKit

/// Battery & Energy: the battery's charge and condition (on Macs that have one), per-app watts from the
/// kernel's energy counters, what keeps the Mac awake, and the drain over time.
struct BatteryEnergyView: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.theme) private var theme
    @AppStorage("energy.sort") private var sort: EnergySort = .power
    @AppStorage(SettingsKey.fahrenheit) private var fahrenheit = false

    var body: some View {
        DetailPage {
            if let s = store.snapshot {
                let groups = store.energyGroups(sort: sort)
                let blockers = sleepBlockers(s)
                VStack(alignment: .leading, spacing: 16) {
                    StatStrip {
                        if let b = s.battery {
                            // A plain ring like the Overview's; the system gauge style adds marker dots.
                            let tint = b.charge < 0.2 ? theme.high : theme.low
                            ZStack {
                                Circle().stroke(tint.opacity(0.2), lineWidth: 8)
                                Circle()
                                    .trim(from: 0, to: min(max(b.charge, 0.004), 1))
                                    .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                    .animation(.smooth(duration: 0.6), value: b.charge)
                                Text(Fmt.percent(b.charge, digits: 0))
                                    .font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
                            }
                            .frame(width: 72, height: 72)
                            .padding(4)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Battery \(Fmt.percent(b.charge, digits: 0))")
                            BigStat(title: "Status", value: batteryStatus(b))
                            if let minutes = b.minutesRemaining {
                                BigStat(title: b.isCharging ? "Until full" : "Remaining", value: Fmt.minutes(minutes))
                            }
                        }
                        if let power = store.systemPower {
                            BigStat(title: "Mac is using", value: Fmt.watts(power), color: theme.mid)
                        }
                        BigStat(title: "Apps", value: Fmt.watts(store.processPower.last ?? 0))
                        if let h = s.battery?.health {
                            BigStat(title: "Health", value: Fmt.percent(h, digits: 0), color: theme.meter(1 - h + 0.3))
                        }
                        BigStat(title: "Preventing sleep", value: "\(blockers.count)",
                                color: blockers.isEmpty ? .primary : theme.mid)
                    }

                    Panel("Power Over Time", symbol: "chart.xyaxis.line") {
                        HistoryChart(series: powerSeries, maxY: nil) { Fmt.watts($0) }
                            .frame(height: 140)
                    }

                    if s.battery != nil {
                        Panel("Charge", symbol: "battery.75percent") {
                            HistoryChart(series: [ChartSeries(name: "Charge", color: theme.low, history: store.batteryCharge)],
                                         maxY: 1) { Fmt.percent($0, digits: 0) }
                                .frame(height: 120)
                        }
                    }

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

                    Panel("Preventing Sleep", symbol: "moon.zzz") {
                        SleepBlockerList(blockers: blockers)
                    }

                    if let b = s.battery {
                        Panel("Battery Details", symbol: "info.circle") {
                            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                                if let c = b.cycleCount { StatRow("Cycle count", "\(c)") }
                                if let max = b.maxCapacity, let design = b.designCapacity { StatRow("Capacity", "\(max) mAh of \(design) mAh design") }
                                if let condition = b.condition { StatRow("Condition", condition) }
                                if let v = b.voltage { StatRow("Voltage", String(format: "%.2f V", v)) }
                                if let a = b.amperage { StatRow("Current", String(format: "%.2f A", a)) }
                                if let w = b.watts { StatRow(b.isCharging ? "Charging power" : "Battery power", String(format: "%.1f W", abs(w))) }
                                if let t = b.temperature { StatRow("Temperature", Fmt.temperature(t, fahrenheit: fahrenheit)) }
                                if let w = b.adapterWatts, w > 0 { StatRow("Power adapter", "\(w) W") }
                            }
                        }
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

    private func sleepBlockers(_ s: SystemSnapshot) -> [SleepBlocker] {
        s.powerAssertions
            .map { SleepBlocker(pid: $0.key, assertions: $0.value.filter(\.preventsSleep)) }
            .filter { !$0.assertions.isEmpty }
            .sorted { $0.pid < $1.pid }
    }
}

func batteryStatus(_ b: BatteryStats) -> String {
    if b.isCharged { return "Charged" }
    if b.isCharging { return "Charging" }
    return b.isPluggedIn ? "Plugged in" : "On battery"
}

private struct SleepBlocker: Identifiable {
    var pid: pid_t
    var assertions: [PowerAssertion]
    var id: pid_t { pid }
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

            // Twelve rows tall whatever the app count; more scroll inside the panel.
            StableRows(items: groups, rows: 12, scrolls: true) { group in
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
            } empty: {
                Text("Measuring…").font(.callout).foregroundStyle(.secondary)
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
    var blockers: [SleepBlocker]

    var body: some View {
        // Room for three blockers whether there are none or many; more scroll inside the panel.
        StableRows(items: blockers, rows: 3, spacing: 8, scrolls: true, estimatedRowHeight: 36) { blocker in
            let name = store.process(blocker.pid).map(store.displayName) ?? "PID \(blocker.pid)"
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.callout.weight(.medium))
                    ForEach(Array(blocker.assertions.enumerated()), id: \.offset) { _, assertion in
                        Text(describe(assertion)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                Button("Show") { store.reveal(blocker.pid) }
                Button("Quit") { store.requestQuit([blocker.pid]) }
            }
            .controlSize(.small)
        } empty: {
            Text("Nothing is keeping your Mac awake.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func describe(_ a: PowerAssertion) -> String {
        var text = a.effect
        if !a.name.isEmpty { text += ": \(a.name)" }
        if let created = a.created { text += " · for \(Fmt.duration(Date().timeIntervalSince(created)))" }
        return text
    }
}
