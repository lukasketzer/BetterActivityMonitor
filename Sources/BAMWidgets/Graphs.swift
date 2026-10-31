import AppIntents
import Charts
import SwiftUI
import SystemKit
import WidgetKit

struct MetricGraphIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "History Graph"
    static let description = IntentDescription("Choose the metric to graph.")

    @Parameter(title: "Metric", default: .cpu)
    var metric: WidgetMetric
}

struct ActivityGraphsIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Activity Graphs"
    static let description = IntentDescription("Choose the metrics to graph, top to bottom.")

    @Parameter(title: "Metrics", default: [.cpu, .gpu, .memory, .disk])
    var metrics: [WidgetMetric]
}

struct GraphEntry: TimelineEntry {
    var system: SystemEntry
    var metrics: [WidgetMetric]
    var samples: [HistorySample]
    var date: Date { system.date }
}

func graphEntry(metrics: [WidgetMetric], context: TimelineProviderContext, record: Bool) -> GraphEntry {
    if context.isPreview { return GraphEntry(system: .placeholder, metrics: metrics, samples: HistoryStore.placeholder) }
    let system = SystemEntry.sample()
    if record { HistoryStore.record(system) }
    return GraphEntry(system: system, metrics: metrics, samples: HistoryStore.load())
}

private func graphTimeline(_ entry: GraphEntry) -> Timeline<GraphEntry> {
    Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60)))
}

struct MetricGraphProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> GraphEntry {
        GraphEntry(system: .placeholder, metrics: [.cpu], samples: HistoryStore.placeholder)
    }
    func snapshot(for configuration: MetricGraphIntent, in context: Context) async -> GraphEntry {
        graphEntry(metrics: [configuration.metric], context: context, record: false)
    }
    func timeline(for configuration: MetricGraphIntent, in context: Context) async -> Timeline<GraphEntry> {
        graphTimeline(graphEntry(metrics: [configuration.metric], context: context, record: true))
    }
}

struct ActivityGraphsProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> GraphEntry {
        GraphEntry(system: .placeholder, metrics: WidgetMetric.defaults, samples: HistoryStore.placeholder)
    }
    func snapshot(for configuration: ActivityGraphsIntent, in context: Context) async -> GraphEntry {
        graphEntry(metrics: configuration.metrics, context: context, record: false)
    }
    func timeline(for configuration: ActivityGraphsIntent, in context: Context) async -> Timeline<GraphEntry> {
        graphTimeline(graphEntry(metrics: configuration.metrics, context: context, record: true))
    }
}

// MARK: Metric presentation

extension WidgetMetric {
    var tint: Color {
        switch self {
        case .cpu: WidgetColor.cpu
        case .gpu: WidgetColor.gpu
        case .memory: WidgetColor.memory
        case .disk: WidgetColor.disk
        case .battery: WidgetColor.battery
        }
    }

    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .gpu: "cube.transparent"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .battery: "battery.75percent"
        }
    }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "Memory"
        case .disk: "Disk"
        case .battery: "Battery"
        }
    }

    /// The app section a tap opens.
    var section: String {
        switch self {
        case .cpu: "cpu"
        case .gpu: "sensors"
        case .memory: "memory"
        case .disk: "disks"
        case .battery: "battery"
        }
    }

    func current(in e: SystemEntry) -> Double? {
        switch self {
        case .cpu: e.cpu
        case .gpu: e.gpu
        case .memory: e.memFraction
        case .disk: e.mainVolume?.usedFraction
        case .battery: e.battery?.charge
        }
    }
}

private struct ChartPoint: Identifiable {
    var date: Date
    var value: Double
    var id: Date { date }
}

// MARK: Chart

/// Rounded hourly bars with dashed grid lines and hour labels, like the Health app. Scales to the data for
/// CPU, which is mostly low.
struct MetricChart: View {
    var metric: WidgetMetric
    var samples: [HistorySample]
    var available: Bool = true
    var showAxis = false
    /// Needed to label the memory axis in GB.
    var memoryTotal: UInt64 = 0

    /// Average per clock hour, so a day is at most 25 bars.
    private var points: [ChartPoint] {
        let calendar = Calendar.current
        let values = samples.compactMap { s in s.value(for: metric).map { (date: s.date, value: $0) } }
        let hours = Dictionary(grouping: values) { calendar.dateInterval(of: .hour, for: $0.date)?.start ?? $0.date }
        return hours.map { hour, group in ChartPoint(date: hour, value: group.map(\.value).reduce(0, +) / Double(group.count)) }
            .sorted { $0.date < $1.date }
    }

    private func upperBound(_ points: [ChartPoint]) -> Double {
        guard metric == .cpu || metric == .gpu else { return 1 }
        return min(1, max(0.2, (points.map(\.value).max() ?? 0) * 1.25))
    }

    private func axisLabel(_ fraction: Double) -> String {
        guard metric == .memory, memoryTotal > 0 else { return WidgetFmt.percent(fraction) }
        return "\(Int((fraction * Double(memoryTotal) / Double(1 << 30)).rounded())) GB"
    }

    var body: some View {
        let pts = points
        if !available || pts.isEmpty {
            Text(available ? "Collecting history…" : "Not available")
                .font(.caption2).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let end = (pts.last?.date ?? .now).addingTimeInterval(3600)
            Chart(pts) { p in
                BarMark(x: .value("Time", p.date, unit: .hour), y: .value(metric.title, p.value), width: .ratio(0.72))
                    .foregroundStyle(metric.tint.gradient)
                    .cornerRadius(2.5)
            }
            .chartYScale(domain: 0...upperBound(pts))
            .chartXScale(domain: end.addingTimeInterval(-24 * 3600)...end)
            .chartXAxis {
                if showAxis {
                    AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                        AxisValueLabel(format: .dateTime.hour(), anchor: .top)
                    }
                }
            }
            .chartYAxis {
                if showAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3])).foregroundStyle(.tertiary)
                        AxisValueLabel {
                            if let v = value.as(Double.self) { Text(axisLabel(v)) }
                        }
                    }
                }
            }
            .chartPlotStyle { $0.padding(.top, 2) }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
            .widgetAccentable()
        }
    }
}

/// Health-style value: big rounded number with a small unit beside it.
struct ValueWithUnit: View {
    var number: String
    var unit: String
    var size: CGFloat

    /// Memory reads as GB in use; everything else as a percentage.
    init(metric: WidgetMetric, entry: SystemEntry, size: CGFloat) {
        self.size = size
        guard let fraction = metric.current(in: entry) else { number = "—"; unit = ""; return }
        if metric == .memory {
            number = WidgetFmt.gigabytes(entry.memUsed); unit = "GB"
        } else {
            number = String(format: "%.0f", fraction * 100); unit = "%"
        }
    }

    init(number: String, unit: String, size: CGFloat) {
        self.number = number; self.unit = unit; self.size = size
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(number)
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(unit)
                .font(.system(size: size * 0.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

private func spanText(_ samples: [HistorySample]) -> String {
    guard let first = samples.first, let last = samples.last, last.date > first.date else { return "Just started" }
    let minutes = Int(last.date.timeIntervalSince(first.date) / 60)
    return minutes >= 90 ? "Last \(minutes / 60) hours" : "Last \(max(minutes, 1)) min"
}

// MARK: Single graph

struct MetricGraphWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "MetricGraph", intent: MetricGraphIntent.self, provider: MetricGraphProvider()) { entry in
            MetricGraphView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("History Graph")
        .description("One metric over the last day. Edit the widget to choose which.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct MetricGraphView: View {
    var entry: GraphEntry
    @Environment(\.widgetFamily) private var family

    private var metric: WidgetMetric { entry.metrics.first ?? .cpu }
    private var value: Double? { metric.current(in: entry.system) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                WidgetHeader(title: metric.title, symbol: metric.symbol, color: metric.tint)
                Spacer()
                if family != .systemSmall { Text(spanText(entry.samples)).font(.caption2).foregroundStyle(.secondary) }
            }
            ValueWithUnit(metric: metric, entry: entry.system, size: family == .systemSmall ? 30 : 38)
            MetricChart(metric: metric, samples: entry.samples, available: value != nil, showAxis: family != .systemSmall,
                        memoryTotal: entry.system.memTotal)
        }
        .opensSection(metric.section)
    }
}

// MARK: Activity graphs

struct ActivityGraphsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ActivityGraphs", intent: ActivityGraphsIntent.self, provider: ActivityGraphsProvider()) { entry in
            ActivityGraphsView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Activity Graphs")
        .description("Several metrics over the last day, stacked. Edit the widget to add or remove some.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct ActivityGraphsView: View {
    var entry: GraphEntry
    @Environment(\.widgetFamily) private var family

    /// Chosen metrics without duplicates or unavailable ones, as many as fit the widget.
    private var metrics: [WidgetMetric] {
        var seen = Set<WidgetMetric>()
        let chosen = entry.metrics.filter { seen.insert($0).inserted && $0.current(in: entry.system) != nil }
        let result = Array(chosen.prefix(family == .systemLarge ? 4 : 2))
        return result.isEmpty ? [.cpu] : result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(metrics, id: \.self) { metric in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        WidgetHeader(title: metric.title, symbol: metric.symbol, color: metric.tint)
                        ValueWithUnit(metric: metric, entry: entry.system, size: 26)
                    }
                    .frame(width: 92, alignment: .leading)
                    MetricChart(metric: metric, samples: entry.samples)
                }
            }
            if family == .systemLarge {
                Text(spanText(entry.samples)).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .opensSection("overview")
    }
}

private func previewEntry(_ metrics: [WidgetMetric]) -> GraphEntry {
    GraphEntry(system: .placeholder, metrics: metrics, samples: HistoryStore.placeholder)
}

#Preview("Graph", as: .systemSmall) { MetricGraphWidget() } timeline: { previewEntry([.cpu]) }
#Preview("Graph", as: .systemMedium) { MetricGraphWidget() } timeline: { previewEntry([.memory]) }
#Preview("Activity", as: .systemMedium) { ActivityGraphsWidget() } timeline: { previewEntry([.cpu, .memory]) }
#Preview("Activity", as: .systemLarge) { ActivityGraphsWidget() } timeline: { previewEntry(WidgetMetric.allCases) }
