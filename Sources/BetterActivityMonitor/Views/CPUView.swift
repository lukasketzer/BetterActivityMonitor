import SwiftUI
import SystemKit

/// Compact CPU box for the overview (btop's CPU box).
struct CPUPanel: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.theme) private var theme
    @AppStorage(SettingsKey.fahrenheit) private var fahrenheit = false

    var body: some View {
        Panel("CPU", symbol: "cpu", destination: .cpu) {
            if let s = store.snapshot {
                HStack(spacing: 10) {
                    if let t = store.cpuTemperatureNow {
                        Label(Fmt.temperature(t, fahrenheit: fahrenheit), systemImage: "thermometer.medium")
                    }
                    Text("Load \(s.cpu.loadAverage.map { Fmt.number($0, digits: 2) }.joined(separator: " "))")
                    Text("Up \(Fmt.duration(s.cpu.uptime))")
                }
                .monospacedDigit()
            }
        } content: {
            if let s = store.snapshot {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(Fmt.percent(s.cpu.total, digits: 0))
                                .font(.system(size: 28, weight: .semibold).monospacedDigit())
                                .foregroundStyle(theme.meter(s.cpu.total))
                                .contentTransition(.numericText())
                            VStack(alignment: .leading, spacing: 0) {
                                Text("user \(Fmt.percent(s.cpu.user, digits: 0))").foregroundStyle(theme.cpuUser)
                                Text("sys \(Fmt.percent(s.cpu.system, digits: 0))").foregroundStyle(theme.cpuSystem)
                            }
                            .font(.caption.monospacedDigit())
                        }
                        HistoryChart(series: cpuSeries(theme: theme), maxY: 1, stacked: true) { Fmt.percent($0, digits: 0) }
                            .frame(minHeight: 80)
                    }
                    .frame(minWidth: 220)
                    CompactCoreGrid()
                        .frame(minWidth: 220, maxWidth: 420)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func cpuSeries(theme: Theme) -> [ChartSeries] {
        [ChartSeries(name: "User", color: theme.cpuUser, history: store.cpuUser),
         ChartSeries(name: "System", color: theme.cpuSystem, history: store.cpuSystem)]
    }
}

/// Overview core list (label, sparkline, percent per core) drawn in one Canvas: as 14 rows of stacked
/// views it cost ~14 ms of layout per frame during window resizing. Hovering a row shows its details.
struct CompactCoreGrid: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.theme) private var theme
    @State private var hover: CGPoint?

    private let rowHeight: CGFloat = 15
    private let rowSpacing: CGFloat = 3
    private let columnSpacing: CGFloat = 12
    private let labelWidth: CGFloat = 26
    private let valueWidth: CGFloat = 34

    var body: some View {
        if let s = store.snapshot {
            let cores = s.cpu.cores
            let columns = cores.count > 8 ? 2 : 1
            let rows = (cores.count + columns - 1) / columns
            Canvas { context, size in
                let columnWidth = (size.width - columnSpacing * CGFloat(columns - 1)) / CGFloat(columns)
                for (index, core) in cores.enumerated() {
                    let cell = frame(index, rows: rows, columnWidth: columnWidth)
                    let kind = s.cpu.coreKinds[safe: index] ?? .standard
                    let midY = cell.midY
                    context.draw(Text("\(kind.rawValue)\(index)").font(.caption2.monospaced()).foregroundStyle(.secondary),
                                 at: CGPoint(x: cell.minX, y: midY), anchor: .leading)
                    context.draw(Text(Fmt.percent(core.total, digits: 0)).font(.caption2.monospacedDigit()),
                                 at: CGPoint(x: cell.maxX, y: midY), anchor: .trailing)
                    let spark = CGRect(x: cell.minX + labelWidth + 5, y: cell.minY + 1.5,
                                       width: max(cell.width - labelWidth - valueWidth - 10, 4), height: rowHeight - 3)
                    let values = store.cores[safe: index]?.values.suffix(40) ?? []
                    drawSparkline(Array(values), in: spark, color: theme.meter(core.total), context: &context)
                }
            }
            .frame(height: CGFloat(rows) * (rowHeight + rowSpacing) - rowSpacing)
            .overlay(alignment: .topLeading) {
                GeometryReader { geo in
                    let columnWidth = (geo.size.width - columnSpacing * CGFloat(columns - 1)) / CGFloat(columns)
                    if let hover, let index = coreIndex(at: hover, rows: rows, columns: columns, columnWidth: columnWidth),
                       let core = cores[safe: index] {
                        let kind = s.cpu.coreKinds[safe: index] ?? .standard
                        let cell = frame(index, rows: rows, columnWidth: columnWidth)
                        Text("Core \(index) (\(kind == .efficiency ? "efficiency" : kind == .performance ? "performance" : "standard")) · user \(Fmt.percent(core.user)) · system \(Fmt.percent(core.system))")
                            .font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .glassCapsule()
                            .fixedSize()
                            .offset(x: min(cell.minX, max(geo.size.width - 260, 0)), y: cell.maxY + 2)
                            .allowsHitTesting(false)
                    }
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                if case .active(let p) = phase { hover = p } else { hover = nil }
            }
        }
    }

    private func frame(_ index: Int, rows: Int, columnWidth: CGFloat) -> CGRect {
        let column = index / rows, row = index % rows
        return CGRect(x: CGFloat(column) * (columnWidth + columnSpacing), y: CGFloat(row) * (rowHeight + rowSpacing),
                      width: columnWidth, height: rowHeight)
    }

    private func coreIndex(at p: CGPoint, rows: Int, columns: Int, columnWidth: CGFloat) -> Int? {
        let column = Int(p.x / (columnWidth + columnSpacing)), row = Int(p.y / (rowHeight + rowSpacing))
        guard column >= 0, column < columns, row >= 0, row < rows else { return nil }
        return column * rows + row
    }

    private func drawSparkline(_ values: [Double], in rect: CGRect, color: Color, context: inout GraphicsContext) {
        guard values.count > 1 else { return }
        let capacity = 40
        let step = rect.width / CGFloat(capacity - 1)
        let offset = CGFloat(capacity - values.count) * step
        var line = Path()
        for (i, v) in values.enumerated() {
            let p = CGPoint(x: rect.minX + offset + CGFloat(i) * step, y: rect.maxY - CGFloat(min(max(v, 0), 1)) * (rect.height - 1))
            if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
        }
        var area = line
        area.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        area.addLine(to: CGPoint(x: rect.minX + offset, y: rect.maxY))
        area.closeSubpath()
        context.fill(area, with: .linearGradient(Gradient(colors: [color.opacity(0.55), color.opacity(0.08)]),
                                                 startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
        context.stroke(line, with: .color(color), lineWidth: 1.2)
    }
}

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

                    Panel("Cores", symbol: "square.grid.3x3") {
                        Text("\(s.cpu.logicalCores) logical")
                    } content: {
                        CoreGrid()
                    }

                    HStack(alignment: .top, spacing: 16) {
                        Panel("System", symbol: "info.circle") {
                            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                                StatRow("Processor", s.cpu.model)
                                StatRow("Cores", coreDescription(s.cpu))
                                StatRow("Load average", s.cpu.loadAverage.map { Fmt.number($0, digits: 2) }.joined(separator: "  "))
                                StatRow("Uptime", Fmt.duration(s.cpu.uptime))
                                StatRow("Processes", "\(s.cpu.processCount)")
                                StatRow("Threads", "\(s.cpu.threadCount)")
                            }
                        }
                        Panel("Top CPU", symbol: "flame") {
                            TopProcessList(entries: store.top(by: \.cpu)) { Fmt.number($0.cpu) + "%" }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    if store.cpuTemperature.points.count > 1 {
                        Panel("CPU Temperature", symbol: "thermometer.medium") {
                            HistoryChart(series: [ChartSeries(name: "Hottest die", color: theme.temperature, history: store.cpuTemperature)],
                                         maxY: nil) { Fmt.temperature($0, fahrenheit: fahrenheit) }
                                .frame(height: 120)
                        }
                    }
                }
                .padding()
            }
        }
    }

    private func coreDescription(_ cpu: CPUStats) -> String {
        if cpu.performanceCores > 0 {
            return "\(cpu.performanceCores) performance + \(cpu.efficiencyCores) efficiency"
        }
        return "\(cpu.physicalCores) physical, \(cpu.logicalCores) logical"
    }
}

/// Clickable "top N" list; clicking jumps to the process in the table.
struct TopProcessList: View {
    @Environment(SystemStore.self) private var store
    var entries: [ProcessEntry]
    var value: (ProcessEntry) -> String

    var body: some View {
        VStack(spacing: 2) {
            ForEach(entries) { entry in
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
            }
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
