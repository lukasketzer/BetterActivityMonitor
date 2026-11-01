import SwiftUI
import SystemKit

enum HistoryRange: String, CaseIterable, Identifiable {
    case hour = "1h", sixHours = "6h", day = "24h", week = "7d", month = "30d"
    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .hour: 3600
        case .sixHours: 6 * 3600
        case .day: 86_400
        case .week: 7 * 86_400
        case .month: 30 * 86_400
        }
    }

    /// Seconds per point: whole minutes, about 360 points per chart.
    var bucket: Int { max(Int(seconds / 360) / 60 * 60, 60) }
}

/// One loaded range of history, read off the main thread.
struct HistoryData {
    var series: [HistoryMetric: [HistoryValue]] = [:]
    var minutes = 0

    subscript(_ metric: HistoryMetric) -> [HistoryValue] { series[metric] ?? [] }

    static func load(from store: HistoryStore, range: ClosedRange<Date>, bucket: Int) async -> HistoryData {
        var data = HistoryData()
        for metric in HistoryMetric.allCases {
            data.series[metric] = await store.series(metric, from: range.lowerBound, to: range.upperBound, bucket: bucket)
        }
        data.minutes = await store.minuteCount()
        return data
    }
}

/// Past minutes from the on-disk history: stacked charts on one time axis, and what used the most.
struct HistoryView: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.theme) private var theme
    @AppStorage("history.range") private var range: HistoryRange = .day
    @AppStorage(SettingsKey.historyEnabled) private var enabled = true
    /// End of the shown range; nil follows the present.
    @State private var end: Date?
    @State private var now = Date()
    @State private var data = HistoryData()
    @State private var hover: Date?
    @State private var selected: Date?
    @State private var loaded = false

    private var shown: ClosedRange<Date> {
        let upper = end ?? now
        return upper.addingTimeInterval(-range.seconds)...upper
    }

    private var bucket: TimeInterval { TimeInterval(range.bucket) }

    var body: some View {
        HStack(spacing: 0) {
            DetailPage {
                VStack(alignment: .leading, spacing: 12) {
                    if !enabled {
                        notice("History is off", "Turn on “Record history” in Settings to keep a minute-by-minute log.")
                    } else if loaded && data.minutes == 0 {
                        notice("Recording has started", "The first minute appears here once it has passed.")
                    }
                    charts
                }
                .padding()
            }
            Divider()
            HistorySidePanel(range: selectedRange ?? shown, title: selectedTitle) { selected = nil }
                .frame(width: 320)
        }
        .toolbar {
            ToolbarItemGroup(placement: .principal) {
                Picker("Range", selection: $range) {
                    ForEach(HistoryRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { page(-1) } label: { Label("Earlier", systemImage: "chevron.left") }
                    .help("Show the previous \(range.rawValue)")
                Button { page(1) } label: { Label("Later", systemImage: "chevron.right") }
                    .help("Show the next \(range.rawValue)")
                    .disabled(end == nil)
                Button("Now") { end = nil; selected = nil }
                    .disabled(end == nil)
            }
        }
        .navigationSubtitle(subtitle)
        .task(id: "\(range.rawValue) \(end?.timeIntervalSince1970 ?? 0) \(Int(now.timeIntervalSince1970))") {
            data = await HistoryData.load(from: store.history, range: shown, bucket: range.bucket)
            loaded = true
        }
        .task {
            // Follow the present: a new minute lands about once a minute.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if end == nil { now = Date() }
            }
        }
        .onChange(of: range) { selected = nil }
    }

    private var subtitle: String {
        let style = Date.FormatStyle.dateTime.month(.abbreviated).day().hour().minute()
        return "\(shown.lowerBound.formatted(style)) – \(shown.upperBound.formatted(style))"
    }

    private var selectedRange: ClosedRange<Date>? {
        guard let selected else { return nil }
        let start = Date(timeIntervalSince1970: floor(selected.timeIntervalSince1970 / bucket) * bucket)
        return start...start.addingTimeInterval(bucket)
    }

    private var selectedTitle: String? {
        guard let r = selectedRange else { return nil }
        let style = Date.FormatStyle.dateTime.weekday(.abbreviated).hour().minute()
        return bucket > 60 ? "\(r.lowerBound.formatted(style)) – \(r.upperBound.formatted(.dateTime.hour().minute()))"
            : r.lowerBound.formatted(style)
    }

    private func page(_ direction: Double) {
        let next = (end ?? Date()).addingTimeInterval(direction * range.seconds)
        end = next >= Date() ? nil : next
        selected = nil
    }

    @ViewBuilder
    private var charts: some View {
        let r = shown
        chart("CPU", symbol: "cpu", [
            TimelineSeries(name: "Peak", color: theme.cpu.opacity(0.45), values: data[.cpuMax]),
            TimelineSeries(name: "Average", color: theme.cpu, values: data[.cpu]),
        ], range: r, maxY: 1) { Fmt.percent($0, digits: 0) }

        chart("Memory", symbol: "memorychip", [
            TimelineSeries(name: "Used", color: theme.memApp, values: data[.memUsed]),
        ], range: r, maxY: 1, bands: data[.memPressure].compactMap { v in
            v.value >= 4 ? (v.date, theme.high) : v.value >= 2 ? (v.date, theme.mid) : nil
        }) { Fmt.percent($0, digits: 0) }

        if !data[.gpu].isEmpty {
            chart("GPU", symbol: "square.stack.3d.up", [
                TimelineSeries(name: "Utilization", color: theme.gpu, values: data[.gpu]),
            ], range: r, maxY: 1) { Fmt.percent($0, digits: 0) }
        }

        chart("Network", symbol: "network", [
            TimelineSeries(name: "Download", color: theme.netIn, values: data[.netIn]),
            TimelineSeries(name: "Upload", color: theme.netOut, values: data[.netOut]),
        ], range: r) { Fmt.rate($0) }

        chart("Disk", symbol: "internaldrive", [
            TimelineSeries(name: "Read", color: theme.diskRead, values: data[.diskRead]),
            TimelineSeries(name: "Write", color: theme.diskWrite, values: data[.diskWrite]),
        ], range: r) { Fmt.rate($0) }

        chart("Power", symbol: "bolt.fill", [
            TimelineSeries(name: "Mac", color: theme.mid, values: data[.power]),
        ], range: r) { Fmt.watts($0) }

        if !data[.battery].isEmpty {
            chart("Battery", symbol: "battery.75percent", [
                TimelineSeries(name: "Charge", color: theme.low, values: data[.battery]),
            ], range: r, maxY: 1) { Fmt.percent($0, digits: 0) }
        }

        if !data[.cpuTempMax].isEmpty {
            chart("Temperature", symbol: "thermometer.medium", [
                TimelineSeries(name: "Hottest CPU die", color: theme.temperature, values: data[.cpuTempMax]),
            ], range: r) { Fmt.number($0, digits: 0) + " °C" }
        }

        TimelineAxis(range: r)
    }

    private func chart(_ title: String, symbol: String, _ series: [TimelineSeries], range: ClosedRange<Date>,
                       maxY: Double? = nil, bands: [(Date, Color)] = [], format: @escaping (Double) -> String) -> some View {
        Panel(title, symbol: symbol) {
            TimelineChart(series: series, range: range, bucket: bucket, maxY: maxY, bands: bands, hover: $hover,
                          onSelect: { selected = $0 }, format: format)
                .frame(height: 90)
        }
    }

    private func notice(_ title: String, _ message: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "clock.arrow.circlepath")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 14)
    }
}

/// What used the most in the shown range, or in the clicked moment.
private struct HistorySidePanel: View {
    @Environment(SystemStore.self) private var store
    @AppStorage("history.ranking") private var ranking: ProcessRanking = .cpu
    var range: ClosedRange<Date>
    var title: String?
    var clearSelection: () -> Void
    @State private var rows: [ProcessSummary] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.map { "Top at \($0)" } ?? "Top over this range")
                .font(.headline)
            if title == nil {
                Text("Click a chart to see one moment.").font(.caption).foregroundStyle(.secondary)
            } else {
                Button("Show Whole Range", action: clearSelection).controlSize(.small)
            }
            Picker("Rank by", selection: $ranking) {
                Text("CPU").tag(ProcessRanking.cpu)
                Text("Memory").tag(ProcessRanking.memory)
                Text("Disk").tag(ProcessRanking.disk)
                Text("Network").tag(ProcessRanking.net)
                Text("Energy").tag(ProcessRanking.energy)
            }
            .labelsHidden()
            if rows.isEmpty {
                Text("Nothing recorded here.").font(.callout).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(rows) { row in
                        Button { reveal(row) } label: {
                            HStack {
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
                        .help(isRunning(row) ? "Show \(row.name) in Processes" : "\(row.name) isn't running anymore")
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding()
        .task(id: "\(range.lowerBound.timeIntervalSince1970) \(range.upperBound.timeIntervalSince1970) \(ranking.rawValue)") {
            rows = await store.history.topProcesses(from: range.lowerBound, to: range.upperBound, by: ranking)
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

    /// The recorded pid may have been reused by another process since; only trust it if the name fits.
    private func isRunning(_ row: ProcessSummary) -> Bool {
        guard let entry = store.process(row.pid) else { return false }
        if let bundle = row.bundle { return AppBundle.path(forExecutable: entry.path) == bundle }
        return store.displayName(entry) == row.name
    }

    private func reveal(_ row: ProcessSummary) {
        if isRunning(row) { store.reveal(row.pid) }
    }
}
