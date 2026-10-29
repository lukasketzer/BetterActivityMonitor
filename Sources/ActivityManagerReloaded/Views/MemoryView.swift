import SwiftUI
import SystemKit

extension MemoryStats {
    func parts(_ theme: Theme) -> [StackedBar.Part] {
        [StackedBar.Part(label: "App", value: Double(app), color: theme.memApp),
         StackedBar.Part(label: "Wired", value: Double(wired), color: theme.memWired),
         StackedBar.Part(label: "Compressed", value: Double(compressed), color: theme.memCompressed),
         StackedBar.Part(label: "Cached files", value: Double(cached), color: theme.memCached)]
    }
}

private func pressureColor(_ pressure: MemoryPressure, _ theme: Theme) -> Color {
    switch pressure {
    case .normal: theme.low
    case .warning: theme.mid
    case .critical: theme.high
    }
}

struct MemoryPanel: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.theme) private var theme

    var body: some View {
        Panel("Memory", symbol: "memorychip", destination: .memory) {
            if let m = store.snapshot?.memory {
                Text("\(Fmt.bytes(m.used)) / \(Fmt.bytes(m.total))").monospacedDigit()
            }
        } content: {
            if let m = store.snapshot?.memory {
                VStack(alignment: .leading, spacing: 8) {
                    StackedBar(parts: m.parts(theme), total: Double(m.total))
                    HStack(alignment: .top, spacing: 10) {
                        VStack(spacing: 3) {
                            LegendItem(color: theme.memApp, label: "App", value: Fmt.bytes(m.app), font: .caption)
                            LegendItem(color: theme.memWired, label: "Wired", value: Fmt.bytes(m.wired), font: .caption)
                            LegendItem(color: theme.memCompressed, label: "Compressed", value: Fmt.bytes(m.compressed), font: .caption)
                        }
                        VStack(spacing: 3) {
                            LegendItem(color: theme.memCached, label: "Cached", value: Fmt.bytes(m.cached), font: .caption)
                            LegendItem(color: .secondary, label: "Free", value: Fmt.bytes(m.free), font: .caption)
                            LegendItem(color: theme.swap, label: "Swap", value: Fmt.bytes(m.swapUsed), font: .caption)
                        }
                    }
                    HStack(spacing: 6) {
                        Text("Pressure").font(.caption).foregroundStyle(.secondary)
                        Text(m.pressure.label).font(.caption.bold()).foregroundStyle(pressureColor(m.pressure, theme))
                    }
                    HistoryChart(series: [ChartSeries(name: "Used", color: pressureColor(m.pressure, theme), history: store.memUsed)],
                                 maxY: 1, showsYAxis: false) { Fmt.percent($0, digits: 0) }
                        .frame(minHeight: 40)
                }
            }
        }
    }
}

struct MemoryView: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.theme) private var theme

    var body: some View {
        DetailPage {
            if let m = store.snapshot?.memory {
                VStack(alignment: .leading, spacing: 16) {
                    StatStrip {
                        BigStat(title: "Used", value: Fmt.bytes(m.used), color: theme.meter(m.usedFraction))
                        BigStat(title: "Physical", value: Fmt.bytes(m.total))
                        BigStat(title: "Cached files", value: Fmt.bytes(m.cached), color: theme.memCached)
                        BigStat(title: "Swap used", value: Fmt.bytes(m.swapUsed), color: theme.swap)
                        BigStat(title: "Pressure", value: m.pressure.label, color: pressureColor(m.pressure, theme))
                        Spacer()
                    }

                    Panel("Breakdown", symbol: "chart.bar.fill") {
                        VStack(alignment: .leading, spacing: 10) {
                            StackedBar(parts: m.parts(theme) + [StackedBar.Part(label: "Free", value: Double(m.free), color: .gray.opacity(0.3))],
                                       total: Double(m.total), height: 22)
                            Grid(alignment: .leading, horizontalSpacing: 30, verticalSpacing: 4) {
                                GridRow {
                                    LegendItem(color: theme.memApp, label: "App memory", value: Fmt.bytes(m.app))
                                    LegendItem(color: theme.memWired, label: "Wired memory", value: Fmt.bytes(m.wired))
                                    LegendItem(color: theme.memCompressed, label: "Compressed", value: Fmt.bytes(m.compressed), font: .caption)
                                }
                                GridRow {
                                    LegendItem(color: theme.memCached, label: "Cached files", value: Fmt.bytes(m.cached))
                                    LegendItem(color: .gray, label: "Free", value: Fmt.bytes(m.free), font: .caption)
                                    LegendItem(color: theme.swap, label: "Swap", value: "\(Fmt.bytes(m.swapUsed)) / \(Fmt.bytes(m.swapTotal))")
                                }
                            }
                        }
                    }

                    Panel("Memory Over Time", symbol: "chart.xyaxis.line") {
                        HistoryChart(series: [
                            ChartSeries(name: "App", color: theme.memApp, history: store.memApp),
                            ChartSeries(name: "Wired", color: theme.memWired, history: store.memWired),
                            ChartSeries(name: "Compressed", color: theme.memCompressed, history: store.memCompressed),
                        ], maxY: Double(m.total), stacked: true) { Fmt.bytes($0) }
                            .frame(height: 180)
                    }

                    HStack(alignment: .top, spacing: 16) {
                        Panel("Virtual Memory", symbol: "arrow.left.arrow.right") {
                            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                                StatRow("Page ins", "\(Fmt.compact(Double(m.pageIns))) · \(Fmt.number(m.pageInsPerSecond, digits: 0))/s")
                                StatRow("Page outs", "\(Fmt.compact(Double(m.pageOuts))) · \(Fmt.number(m.pageOutsPerSecond, digits: 0))/s")
                                StatRow("Compressions", "\(Fmt.number(m.compressionsPerSecond, digits: 0))/s")
                                StatRow("Swap", "\(Fmt.bytes(m.swapUsed)) of \(Fmt.bytes(m.swapTotal))")
                            }
                            if store.swapUsed.points.count > 1 {
                                HistoryChart(series: [ChartSeries(name: "Swap", color: theme.swap, history: store.swapUsed)],
                                             maxY: nil) { Fmt.bytes($0) }
                                    .frame(height: 70)
                            }
                        }
                        Panel("Top Memory", symbol: "memorychip") {
                            TopProcessList(entries: store.topMemory(count: 8)) { Fmt.bytes($0.memory) }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
            }
        }
    }
}
