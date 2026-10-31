import SwiftUI
import SystemKit
import WidgetKit

/// Everything at a glance in the two biggest sizes: CPU, GPU and memory with their day of history, plus
/// disks and battery.
struct OverviewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Overview", provider: OverviewProvider()) { entry in
            OverviewView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("System Overview")
        .description("CPU, GPU, memory, disks and battery in one widget.")
        .supportedFamilies([.systemLarge, .systemExtraLarge])
    }
}

/// The same overview with level bars instead of history charts.
struct StatsOverviewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OverviewStats", provider: OverviewProvider()) { entry in
            OverviewView(entry: entry, showsHistory: false).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("System Stats")
        .description("CPU, GPU, memory, disks and battery as current numbers and bars, without history.")
        .supportedFamilies([.systemLarge, .systemExtraLarge])
    }
}

struct OverviewProvider: TimelineProvider {
    func placeholder(in context: Context) -> GraphEntry {
        GraphEntry(system: .placeholder, metrics: [], samples: HistoryStore.placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (GraphEntry) -> Void) {
        completion(graphEntry(metrics: [], context: context, record: false))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GraphEntry>) -> Void) {
        let entry = graphEntry(metrics: [], context: context, record: true)
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
}

struct OverviewView: View {
    var entry: GraphEntry
    /// False for System Stats: level bars instead of the day's history.
    var showsHistory = true
    @Environment(\.widgetFamily) private var family

    private var system: SystemEntry { entry.system }
    private var wide: Bool { family == .systemExtraLarge }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                cpuTile
                gpuTile
                if wide { memoryTile }
            }
            HStack(spacing: 8) {
                if !wide { memoryTile }
                diskTile
                if wide {
                    if system.battery != nil { batteryTile } else { uptimeTile }
                }
            }
            if !wide {
                footer
            }
        }
    }

    // MARK: Tiles

    private var cpuTile: some View {
        Tile(title: "CPU", symbol: "cpu", color: WidgetColor.cpu, section: "cpu") {
            HStack(alignment: .firstTextBaseline) {
                ValueWithUnit(metric: .cpu, entry: system, size: 28)
                Spacer()
                Text("Load \(load(0))").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
            if showsHistory {
                MetricChart(metric: .cpu, samples: entry.samples, showAxis: wide)
            } else {
                CapacityBar(fraction: system.cpu, color: WidgetColor.cpu)
                Spacer(minLength: 0)
                Text("Load \(load(0))  \(load(1))  \(load(2))")
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
            }
        }
    }

    private var gpuTile: some View {
        Tile(title: "GPU", symbol: "cube.transparent", color: WidgetColor.gpu, section: "sensors") {
            ValueWithUnit(metric: .gpu, entry: system, size: 28)
            if showsHistory {
                MetricChart(metric: .gpu, samples: entry.samples, available: system.gpu != nil, showAxis: wide)
            } else {
                CapacityBar(fraction: system.gpu ?? 0, color: WidgetColor.gpu)
                Spacer(minLength: 0)
            }
        }
    }

    private var memoryTile: some View {
        Tile(title: "Memory", symbol: "memorychip", color: WidgetColor.memory, section: "memory") {
            HStack(alignment: .firstTextBaseline) {
                ValueWithUnit(metric: .memory, entry: system, size: 28)
                Spacer()
                Text("of \(WidgetFmt.bytes(system.memTotal))").font(.caption2).foregroundStyle(.secondary)
            }
            MemoryBar(entry: system, height: 6)
            if wide || !showsHistory {
                HStack(spacing: 10) {
                    ForEach(system.memoryParts, id: \.name) { part in
                        HStack(spacing: 3) {
                            Circle().fill(part.color).frame(width: 6, height: 6)
                            Text(part.name).foregroundStyle(.secondary)
                            Text(WidgetFmt.bytes(part.value)).monospacedDigit()
                        }
                    }
                }
                .font(.system(size: 9))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            if showsHistory {
                MetricChart(metric: .memory, samples: entry.samples, showAxis: wide, memoryTotal: system.memTotal)
            } else {
                Spacer(minLength: 0)
                Text(system.swapUsed > 0 ? "Swap \(WidgetFmt.bytes(system.swapUsed))" : "No swap used")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var diskTile: some View {
        Tile(title: "Storage", symbol: "internaldrive", color: WidgetColor.disk, section: "disks") {
            if let main = system.mainVolume {
                let free = WidgetFmt.diskValue(main.available)
                ValueWithUnit(number: free.number, unit: "\(free.unit) free", size: 24)
            }
            Spacer(minLength: 0)
            ForEach(system.volumes.prefix(wide ? 2 : 1), id: \.self) { volume in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(volume.name).lineLimit(1)
                        Spacer()
                        Text(WidgetFmt.percent(volume.usedFraction)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.caption2)
                    CapacityBar(fraction: volume.usedFraction, color: WidgetColor.disk, height: 5)
                }
            }
        }
    }

    @ViewBuilder private var batteryTile: some View {
        if let b = system.battery {
            Tile(title: "Battery", symbol: b.isCharging ? "bolt.fill" : "battery.75percent",
                 color: WidgetColor.battery, section: "battery") {
                HStack(spacing: 10) {
                    Ring(fraction: b.charge, color: WidgetColor.battery, lineWidth: 7)
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        ValueWithUnit(number: String(format: "%.0f", b.charge * 100), unit: "%", size: 24)
                        Text(batteryText(b)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if let health = b.health {
                    Text("Health \(WidgetFmt.percent(health))\(b.cycleCount.map { " · \($0) cycles" } ?? "")")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }

    private var uptimeTile: some View {
        Tile(title: "Uptime", symbol: "clock", color: .orange, section: "cpu") {
            uptimeText(size: 24)
            Spacer(minLength: 0)
            Text("Load \(load(0))  \(load(1))  \(load(2))")
                .font(.caption2).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
        }
    }

    /// Battery in one line, so the large size has room for the GPU graph.
    private var footer: some View {
        HStack(spacing: 6) {
            if let b = system.battery {
                Image(systemName: b.isCharging ? "bolt.fill" : "battery.75percent")
                    .foregroundStyle(WidgetColor.battery).widgetAccentable()
                Text(WidgetFmt.percent(b.charge)).fontWeight(.semibold).monospacedDigit()
                Text(batteryText(b)).foregroundStyle(.secondary)
            }
            Spacer()
            UpdatedFooter(date: entry.date)
        }
        .font(.caption)
        .lineLimit(1)
    }

    // MARK: Helpers

    /// "3d 04:12:09"-style uptime whose clock part keeps ticking without a reload.
    private func uptimeText(size: CGFloat) -> some View {
        let days = Int(system.date.timeIntervalSince(system.bootDate)) / 86400
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            if days > 0 {
                Text("\(days)d").font(.system(size: size, weight: .semibold, design: .rounded))
            }
            Text(system.bootDate.addingTimeInterval(Double(days) * 86400), style: .timer)
                .font(.system(size: size, weight: days > 0 ? .regular : .semibold, design: .rounded))
                .foregroundStyle(days > 0 ? .secondary : .primary)
        }
        .monospacedDigit()
        .lineLimit(1)
    }

    private func load(_ index: Int) -> String {
        index < system.loadAverage.count ? system.loadAverage[index].formatted(.number.precision(.fractionLength(2))) : "—"
    }

    private func batteryText(_ b: BatteryInfo) -> String {
        if b.isCharging, let m = b.minutesRemaining { return "\(WidgetFmt.minutes(m)) to full" }
        if b.isPluggedIn { return b.charge >= 0.99 ? "Charged" : "Plugged in" }
        if let m = b.minutesRemaining { return "\(WidgetFmt.minutes(m)) left" }
        return "On battery"
    }
}

/// A rounded card inside the overview; each one links to its section in the app.
private struct Tile<Content: View>: View {
    var title: String
    var symbol: String
    var color: Color
    var section: String
    @ViewBuilder var content: Content

    var body: some View {
        Link(destination: URL(string: "betteractivitymonitor://\(section)")!) {
            VStack(alignment: .leading, spacing: 5) {
                WidgetHeader(title: title, symbol: symbol, color: color)
                content
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private let previewEntry = GraphEntry(system: .placeholder, metrics: [], samples: HistoryStore.placeholder)
#Preview("Overview", as: .systemLarge) { OverviewWidget() } timeline: { previewEntry }
#Preview("Overview", as: .systemExtraLarge) { OverviewWidget() } timeline: { previewEntry }
