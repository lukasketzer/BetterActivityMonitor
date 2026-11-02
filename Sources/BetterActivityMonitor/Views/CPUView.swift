import SwiftUI
import SystemKit

/// Per-core small multiples. Clicking a core shows its value in a popover-free tooltip.
struct CoreGrid: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.theme) private var theme
    var compact = false

    var body: some View {
        if let s = store.snapshot {
            let columns = Array(repeating: GridItem(.flexible(minimum: 60), spacing: 6),
                                count: compact ? (s.cpu.cores.count > 8 ? 2 : 1) : min(max(s.cpu.cores.count / 2, 2), 5))
            LazyVGrid(columns: columns, spacing: compact ? 3 : 8) {
                ForEach(Array(s.cpu.cores.enumerated()), id: \.offset) { index, core in
                    let kind = s.cpu.coreKinds[safe: index] ?? .standard
                    let history = store.cores[safe: index]
                    if compact {
                        HStack(spacing: 5) {
                            Text("\(kind.rawValue)\(index)").font(.caption2.monospaced()).foregroundStyle(.secondary)
                                .frame(width: 26, alignment: .leading)
                            Sparkline(values: history?.values.suffix(40).map { $0 } ?? [], color: theme.meter(core.total), capacity: 40)
                                .frame(maxWidth: .infinity, minHeight: 12, maxHeight: 12)
                            Text(Fmt.percent(core.total, digits: 0)).font(.caption2.monospacedDigit())
                                .frame(width: 34, alignment: .trailing)
                        }
                        .help("Core \(index) (\(kind == .efficiency ? "efficiency" : kind == .performance ? "performance" : "standard")): user \(Fmt.percent(core.user)), system \(Fmt.percent(core.system))")
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Core \(index)").font(.caption.weight(.medium))
                                if kind != .standard {
                                    Text(kind == .efficiency ? "E" : "P")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .glassCapsule(tint: (kind == .efficiency ? theme.low : theme.cpu).opacity(0.5))
                                }
                                Spacer()
                                Text(Fmt.percent(core.total, digits: 0)).font(.caption.monospacedDigit())
                                    .foregroundStyle(theme.meter(core.total))
                            }
                            Sparkline(values: history?.values ?? [], color: theme.meter(core.total), capacity: history?.capacity)
                                .frame(height: 44)
                                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 4))
                        }
                        .padding(8)
                        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .help("user \(Fmt.percent(core.user)) · system \(Fmt.percent(core.system))")
                    }
                }
            }
        }
    }
}

struct CPUView: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.theme) private var theme
    @AppStorage(SettingsKey.fahrenheit) private var fahrenheit = false
    @AppStorage(SettingsKey.cpuCoresExpanded) private var coresExpanded = false

    var body: some View {
        DetailPage {
            if let s = store.snapshot {
                VStack(alignment: .leading, spacing: 16) {
                    StatStrip {
                        BigStat(title: "Total", value: Fmt.percent(s.cpu.total), color: theme.meter(s.cpu.total))
                        BigStat(title: "User", value: Fmt.percent(s.cpu.user), color: theme.cpuUser)
                        BigStat(title: "System", value: Fmt.percent(s.cpu.system), color: theme.cpuSystem)
                        BigStat(title: "Idle", value: Fmt.percent(max(0, 1 - s.cpu.total)))
                        if let t = store.cpuTemperatureNow {
                            BigStat(title: "Temperature", value: Fmt.temperature(t, fahrenheit: fahrenheit), color: theme.temperature)
                        }
                        Spacer()
                    }

                    Panel("CPU Load", symbol: "chart.xyaxis.line") {
                        HistoryChart(series: [
                            ChartSeries(name: "User", color: theme.cpuUser, history: store.cpuUser),
                            ChartSeries(name: "System", color: theme.cpuSystem, history: store.cpuSystem),
                        ], maxY: 1, stacked: true) { Fmt.percent($0, digits: 0) }
                            .frame(height: 180)
                    }

                    Panel("Top CPU", symbol: "flame") {
                        TopProcessList(entries: store.top(by: \.cpu)) { Fmt.number($0.cpu) + "%" }
                    }

                    Panel("Cores", symbol: "square.grid.3x3", expanded: $coresExpanded) {
                        Text("\(s.cpu.logicalCores) logical")
                    } content: {
                        CoreGrid()
                    }
                }
                .padding()
            }
        }
    }
}

/// Clickable "top N" list; clicking jumps to the process in the table. Always as tall as `rows` rows.
struct TopProcessList: View {
    @Environment(SystemStore.self) private var store
    var entries: [ProcessEntry]
    var rows = 5
    var value: (ProcessEntry) -> String

    var body: some View {
        StableRows(items: entries, rows: rows) { entry in
            Button {
                store.reveal(entry.pid)
            } label: {
                HStack(spacing: 6) {
                    if let icon = store.apps[entry.pid]?.icon {
                        Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "terminal").font(.caption).frame(width: 16).foregroundStyle(.tertiary)
                    }
                    Text(store.displayName(entry)).lineLimit(1)
                    Spacer()
                    Text(value(entry)).monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.callout)
                .padding(.vertical, 3)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(HoverRowStyle())
            .help("Show \(store.displayName(entry)) (PID \(entry.pid))")
        } empty: {
            Text("Measuring…").font(.callout).foregroundStyle(.secondary)
        }
    }
}

struct HoverRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverRow(configuration: configuration)
    }

    private struct HoverRow: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: 5).fill(hovering || configuration.isPressed ? Color.primary.opacity(0.07) : .clear))
                .onHover { hovering = $0 }
        }
    }
}
