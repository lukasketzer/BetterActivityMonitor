import AppIntents
import SwiftUI
import WidgetKit

struct ActivityStatsIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Activity Stats"
    static let description = IntentDescription("Choose the metrics to show, top to bottom.")

    @Parameter(title: "Metrics", default: [.cpu, .gpu, .memory, .disk, .battery])
    var metrics: [WidgetMetric]
}

struct ActivityStatsProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> GraphEntry {
        GraphEntry(system: .placeholder, metrics: WidgetMetric.allCases, samples: [])
    }

    func snapshot(for configuration: ActivityStatsIntent, in context: Context) async -> GraphEntry {
        graphEntry(metrics: configuration.metrics, context: context, record: false)
    }

    // Still records history, so graph widgets added later start with data.
    func timeline(for configuration: ActivityStatsIntent, in context: Context) async -> Timeline<GraphEntry> {
        let entry = graphEntry(metrics: configuration.metrics, context: context, record: true)
        return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60)))
    }
}

/// Activity Graphs without the charts: one line per metric with its current value and a level bar.
struct ActivityStatsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ActivityStats", intent: ActivityStatsIntent.self, provider: ActivityStatsProvider()) { entry in
            ActivityStatsView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Activity Stats")
        .description("Current numbers with level bars, without history. Edit the widget to add or remove some.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct ActivityStatsView: View {
    var entry: GraphEntry
    @Environment(\.widgetFamily) private var family

    /// Chosen metrics without duplicates or unavailable ones, as many as fit the widget.
    private var metrics: [WidgetMetric] {
        var seen = Set<WidgetMetric>()
        let chosen = entry.metrics.filter { seen.insert($0).inserted && $0.current(in: entry.system) != nil }
        let result = Array(chosen.prefix(family == .systemLarge ? 5 : 3))
        return result.isEmpty ? [.cpu] : result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemLarge ? 14 : 8) {
            ForEach(metrics, id: \.self) { metric in
                Link(destination: URL(string: "betteractivitymonitor://\(metric.section)")!) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline) {
                            WidgetHeader(title: metric.title, symbol: metric.symbol, color: metric.tint)
                            Spacer()
                            ValueWithUnit(metric: metric, entry: entry.system, size: family == .systemLarge ? 26 : 20)
                        }
                        CapacityBar(fraction: metric.current(in: entry.system) ?? 0, color: metric.tint)
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            if family == .systemLarge {
                UpdatedFooter(date: entry.date)
            }
        }
    }
}

private let previewEntry = GraphEntry(system: .placeholder, metrics: WidgetMetric.allCases, samples: [])
#Preview("Stats", as: .systemMedium) { ActivityStatsWidget() } timeline: { previewEntry }
#Preview("Stats", as: .systemLarge) { ActivityStatsWidget() } timeline: { previewEntry }
#Preview("System Stats", as: .systemExtraLarge) { StatsOverviewWidget() } timeline: { previewEntry }
