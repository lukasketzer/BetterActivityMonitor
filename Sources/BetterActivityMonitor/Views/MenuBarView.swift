import SwiftUI

struct MenuBarLabel: View {
    var store: SystemStore
    @AppStorage(SettingsKey.menuBarItems) private var items = MenuBarItems.default
    @AppStorage(SettingsKey.menuBarStyle) private var style: MenuBarStyle = .rings
    @AppStorage(SettingsKey.menuBarColored) private var colored = false
    @AppStorage(SettingsKey.menuBarSymbols) private var symbols = true
    @AppStorage(SettingsKey.theme) private var themeID = Theme.system.id
    @AppStorage(SettingsKey.fahrenheit) private var fahrenheit = false
    @Environment(\.displayScale) private var scale
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let glyph = MenuBarGlyph(readings: store.menuBarReadings(items.enabled, fahrenheit: fahrenheit),
                                 style: style, colored: colored, symbols: symbols, theme: Theme.named(themeID))
        if let image = MenuBarRenderer.image(glyph, scale: scale, colorScheme: colorScheme) {
            Image(nsImage: image)
        } else {
            Image(systemName: "gauge.with.dots.needle.33percent")
        }
    }
}

extension SystemStore {
    /// The chosen metrics this Mac can provide, in the chosen order. Empty until the first sample.
    func menuBarReadings(_ metrics: [MenuBarMetric], fahrenheit: Bool) -> [MenuBarReading] {
        guard let snapshot else { return [] }
        let inputs = MenuBarInputs(snapshot, temperature: cpuTemperatureNow)
        return metrics.compactMap { inputs.reading($0, fahrenheit: fahrenheit) }
    }
}

struct MenuBarView: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @AppStorage(SettingsKey.theme) private var themeID = Theme.system.id
    @AppStorage(SettingsKey.menuBarItems) private var items = MenuBarItems.default

    /// Graph rows follow the menu bar's metrics and order; the full set when none of them has a graph here.
    private var graphed: [MenuBarMetric] {
        let available: [MenuBarMetric] = [.cpu, .memory, .network, .gpu]
        let chosen = items.enabled.filter(available.contains)
        return chosen.isEmpty ? available : chosen
    }

    var body: some View {
        let theme = Theme.named(themeID)
        VStack(alignment: .leading, spacing: 12) {
            if let s = store.snapshot {
                ForEach(graphed) { metric in
                    switch metric {
                    case .cpu: row("CPU", Fmt.percent(s.cpu.total), values: store.cpuTotal.values, color: theme.cpu)
                    case .memory:
                        row("Memory", "\(Fmt.bytes(s.memory.used)) · \(s.memory.pressure.label)", values: store.memUsed.values, color: theme.memApp)
                    case .network:
                        row("Network", "↓ \(Fmt.rate(s.network.rateIn))  ↑ \(Fmt.rate(s.network.rateOut))",
                            values: store.netIn.values, color: theme.netIn, maxValue: 0)
                    case .gpu:
                        if let g = s.gpu { row("GPU", Fmt.percent(g.utilization), values: store.gpu.values, color: theme.gpu) }
                    default: EmptyView()
                    }
                }

                Divider()
                Text("Top processes").font(.caption).foregroundStyle(.secondary)
                TopProcessList(entries: store.top(by: \.cpu, count: 6)) { Fmt.number($0.cpu) + "%" }
            } else {
                ProgressView()
            }
            Divider()
            HStack {
                Button("Open Monitor") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                Spacer()
                SettingsLink { Text("Settings…") }
                Button("Quit") { NSApp.terminate(nil) }
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 320)
        .environment(\.theme, theme)
        .onChange(of: store.section) { _, _ in
            // Clicking a top process navigates the main window; bring it forward.
            openWindow(id: "main")
            NSApp.activate()
        }
    }

    private func row(_ title: String, _ value: String, values: [Double], color: Color, maxValue: Double = 1) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.callout.weight(.medium))
                Spacer()
                Text(value).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            Sparkline(values: Array(values.suffix(60)), maxValue: maxValue, color: color, capacity: 60)
                .frame(height: 26)
        }
    }
}
