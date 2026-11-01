import SwiftUI
import SystemKit

/// The range the resource pages show. Live while history recording is off.
private struct EffectiveRange {
    @AppStorage(SettingsKey.historyEnabled) var enabled = false
    @AppStorage(SettingsKey.historyRange) var stored: HistoryRange = .live
}

/// `Live | 1h | 24h | 7d | 30d` for a page's charts and top lists. One choice for every page, so switching
/// pages keeps the time span. Hidden while history recording is off.
struct HistoryRangePicker: View {
    @AppStorage(SettingsKey.historyEnabled) private var enabled = false
    @AppStorage(SettingsKey.historyRange) private var range: HistoryRange = .live

    var body: some View {
        if enabled {
            Picker("Range", selection: $range) {
                ForEach(HistoryRange.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Show the live graph or the recorded history")
        }
    }
}

struct HistorySeries {
    var metric: HistoryMetric
    var name: String
    var color: Color
}

/// A page's chart: `live` in Live mode, otherwise the same quantities from the minute history.
struct RangedChart<Live: View>: View {
    @Environment(SystemStore.self) private var store
    @AppStorage(SettingsKey.historyEnabled) private var enabled = false
    @AppStorage(SettingsKey.historyRange) private var range: HistoryRange = .live
    var series: [HistorySeries]
    var maxY: Double?
    /// Extra metrics `bands` reads (they aren't drawn as lines).
    var bandMetrics: [HistoryMetric] = []
    var bands: (HistoryData) -> [(Date, Color)] = { _ in [] }
    var format: (Double) -> String
    @ViewBuilder var live: Live

    @State private var data = HistoryData()
    @State private var shown = Date()...Date()
    @State private var hover: Date?
    @State private var loaded = false

    private var active: HistoryRange { enabled ? range : .live }

    var body: some View {
        if active == .live {
            live
        } else {
            VStack(spacing: 2) {
                TimelineChart(series: series.map { TimelineSeries(name: $0.name, color: $0.color, values: data[$0.metric]) },
                              range: shown, bucket: TimeInterval(active.bucket), maxY: maxY, bands: bands(data),
                              hover: $hover, format: format)
                TimelineAxis(range: shown)
            }
            .overlay {
                if loaded && series.allSatisfy({ data[$0.metric].isEmpty }) {
                    Text(data.minutes == 0 ? "No history recorded yet." : "Nothing recorded in this range.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .task(id: active) {
                // New minutes arrive once a minute; follow the present.
                while !Task.isCancelled {
                    let now = Date()
                    let range = now.addingTimeInterval(-active.seconds)...now
                    data = await HistoryData.load(from: store.history, metrics: series.map(\.metric) + bandMetrics,
                                                  range: range, bucket: active.bucket)
                    shown = range
                    loaded = true
                    try? await Task.sleep(for: .seconds(60))
                }
            }
        }
    }
}

/// A page's "top" list: `live` in Live mode, otherwise apps ranked over the chosen range.
struct RangedTopList<Live: View>: View {
    @AppStorage(SettingsKey.historyEnabled) private var enabled = false
    @AppStorage(SettingsKey.historyRange) private var range: HistoryRange = .live
    var ranking: ProcessRanking
    var count = 8
    @ViewBuilder var live: Live

    var body: some View {
        if !enabled || range == .live {
            live
        } else {
            HistoryTopList(range: range, ranking: ranking, count: count)
        }
    }
}

private struct HistoryTopList: View {
    @Environment(SystemStore.self) private var store
    var range: HistoryRange
    var ranking: ProcessRanking
    var count: Int
    @State private var rows: [ProcessSummary] = []
    @State private var loaded = false

    var body: some View {
        VStack(spacing: 2) {
            if loaded && rows.isEmpty {
                Text("Nothing recorded in the last \(range.rawValue).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(rows) { row in
                Button { reveal(row) } label: {
                    HStack(spacing: 6) {
                        icon(row)
                        Text(row.name).lineLimit(1)
                        Spacer()
                        Text(value(row)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    .padding(.vertical, 3)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(HoverRowStyle())
                .help(isRunning(row) ? "Show \(row.name)" : "\(row.name) isn't running now")
            }
        }
        .task(id: "\(range.rawValue) \(ranking.rawValue)") {
            while !Task.isCancelled {
                let now = Date()
                rows = await store.history.topProcesses(from: now.addingTimeInterval(-range.seconds), to: now,
                                                        by: ranking, limit: count)
                loaded = true
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    @ViewBuilder
    private func icon(_ row: ProcessSummary) -> some View {
        if let bundle = row.bundle {
            Image(nsImage: NSWorkspace.shared.icon(forFile: bundle)).resizable().frame(width: 16, height: 16)
        } else {
            Image(systemName: "terminal").font(.caption).frame(width: 16).foregroundStyle(.tertiary)
        }
    }

    private func value(_ row: ProcessSummary) -> String {
        switch ranking {
        case .cpu: Fmt.number(row.cpu) + "%"
        case .memory: Fmt.bytes(row.memoryPeak)
        case .disk: Fmt.bytes(row.diskBytes)
        case .net: Fmt.bytes(row.netBytes)
        case .energy: Fmt.energy(row.energy)
        }
    }

    /// The recorded pid may since belong to another process; trust it only if the app or name matches.
    private func isRunning(_ row: ProcessSummary) -> Bool {
        guard let entry = store.process(row.pid) else { return false }
        if let bundle = row.bundle { return AppBundle.path(forExecutable: entry.path) == bundle }
        return entry.name == row.name
    }

    private func reveal(_ row: ProcessSummary) {
        if isRunning(row) { store.reveal(row.pid) }
    }
}
