import AppIntents
import SwiftUI
import WidgetKit

/// A metric the rings widget can draw. Only values the widget can read inside the sandbox.
enum WidgetMetric: String, AppEnum, CaseIterable {
    case cpu, gpu, memory, disk, battery

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Metric"
    static let caseDisplayRepresentations: [WidgetMetric: DisplayRepresentation] = [
        .cpu: DisplayRepresentation(title: "CPU", image: .init(systemName: "cpu")),
        .gpu: DisplayRepresentation(title: "GPU", image: .init(systemName: "cube.transparent")),
        .memory: DisplayRepresentation(title: "Memory", image: .init(systemName: "memorychip")),
        .disk: DisplayRepresentation(title: "Startup Disk", image: .init(systemName: "internaldrive")),
        .battery: DisplayRepresentation(title: "Battery", image: .init(systemName: "battery.75percent")),
    ]

    static let defaults: [WidgetMetric] = [.cpu, .gpu, .memory, .disk]
    static let maxRings = 4
}

struct SystemRingsIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "System Rings"
    static let description = IntentDescription("Choose up to four metrics, outermost ring first.")

    @Parameter(title: "Metrics", default: [.cpu, .gpu, .memory, .disk])
    var metrics: [WidgetMetric]

    @Parameter(title: "Update", default: .oneMinute)
    var interval: RefreshInterval
}

struct RingsEntry: TimelineEntry {
    var system: SystemEntry
    var metrics: [WidgetMetric]
    var date: Date { system.date }
}

struct RingsProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> RingsEntry {
        RingsEntry(system: .placeholder, metrics: WidgetMetric.defaults)
    }

    func snapshot(for configuration: SystemRingsIntent, in context: Context) async -> RingsEntry {
        RingsEntry(system: context.isPreview ? .placeholder : .sample(), metrics: configuration.metrics)
    }

    func timeline(for configuration: SystemRingsIntent, in context: Context) async -> Timeline<RingsEntry> {
        let entry = RingsEntry(system: .sample(), metrics: configuration.metrics)
        return Timeline(entries: [entry], policy: refreshPolicy(configuration.interval, kind: "SystemRings"))
    }
}

/// One drawn ring: the metric's current value and how to label it.
private struct RingData: Identifiable {
    var metric: WidgetMetric
    var fraction: Double
    var color: Color
    var symbol: String
    var title: String
    var id: WidgetMetric { metric }
}

private extension WidgetMetric {
    func data(in e: SystemEntry) -> RingData? {
        switch self {
        case .cpu: RingData(metric: self, fraction: e.cpu, color: WidgetColor.cpu, symbol: "cpu", title: "CPU")
        case .gpu: e.gpu.map {
            RingData(metric: self, fraction: $0, color: WidgetColor.gpu, symbol: "cube.transparent", title: "GPU")
        }
        case .memory: RingData(metric: self, fraction: e.memFraction, color: WidgetColor.memory, symbol: "memorychip", title: "Memory")
        case .disk: e.mainVolume.map {
            RingData(metric: self, fraction: $0.usedFraction, color: WidgetColor.disk, symbol: "internaldrive", title: "Disk")
        }
        case .battery: e.battery.map {
            RingData(metric: self, fraction: $0.charge, color: WidgetColor.battery, symbol: "battery.75percent", title: "Battery")
        }
        }
    }
}

struct SystemRingsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "SystemRings", intent: SystemRingsIntent.self, provider: RingsProvider()) { entry in
            SystemRingsView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("System Rings")
        .description("Rings for the metrics you choose. Edit the widget to add or remove some.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct SystemRingsView: View {
    var entry: RingsEntry
    @Environment(\.widgetFamily) private var family

    /// Chosen metrics without duplicates or unavailable ones (no battery on a desktop Mac), at most four.
    private var rings: [RingData] {
        var seen = Set<WidgetMetric>()
        let chosen = entry.metrics.filter { seen.insert($0).inserted }.compactMap { $0.data(in: entry.system) }
        let result = Array(chosen.prefix(WidgetMetric.maxRings))
        return result.isEmpty ? [WidgetMetric.cpu.data(in: entry.system)].compactMap { $0 } : result
    }

    var body: some View {
        switch family {
        case .systemMedium:
            HStack(spacing: 18) {
                ringStack.frame(maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(rings) { ring in
                        HStack(spacing: 6) {
                            Image(systemName: ring.symbol).foregroundStyle(ring.color).widgetAccentable().frame(width: 18)
                            Text(ring.title).foregroundStyle(.secondary)
                            Spacer(minLength: 4)
                            Text(WidgetFmt.percent(ring.fraction)).fontWeight(.semibold).monospacedDigit()
                        }
                        .font(.callout)
                    }
                    Spacer(minLength: 0)
                    UpdatedFooter(date: entry.date)
                }
            }
            .opensSection("overview")
        default:
            ringStack.opensSection("overview")
        }
    }

    private var ringStack: some View {
        let list = rings
        let lineWidth: CGFloat = list.count > 3 ? 10 : 13
        let step = lineWidth + 2
        return ZStack {
            ForEach(Array(list.enumerated()), id: \.element.id) { index, ring in
                Ring(fraction: ring.fraction, color: ring.color, lineWidth: lineWidth)
                    .padding(CGFloat(index) * step)
            }
            // A single ring has room for its value in the middle.
            if let only = list.first, list.count == 1 {
                VStack(spacing: 0) {
                    Image(systemName: only.symbol).foregroundStyle(only.color).widgetAccentable()
                    Text(WidgetFmt.percent(only.fraction))
                        .font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private let previewAll = RingsEntry(system: .placeholder, metrics: WidgetMetric.allCases)
#Preview("Rings", as: .systemSmall) { SystemRingsWidget() } timeline: { RingsEntry(system: .placeholder, metrics: WidgetMetric.defaults) }
#Preview("Four rings", as: .systemSmall) { SystemRingsWidget() } timeline: { previewAll }
#Preview("Rings", as: .systemMedium) { SystemRingsWidget() } timeline: { previewAll }
