import SwiftUI

extension SystemStore {
    /// The chosen metrics this Mac can provide, in the chosen order. Empty until the first sample.
    func menuBarReadings(_ metrics: [MenuBarMetric], fahrenheit: Bool) -> [MenuBarReading] {
        guard let snapshot else { return [] }
        let inputs = MenuBarInputs(snapshot, temperature: cpuTemperatureNow)
        return metrics.compactMap { inputs.reading($0, fahrenheit: fahrenheit) }
    }
}

/// The menu bar item's popover (see `StatusItemController`).
struct MenuBarView: View {
    /// Closes the popover.
    var close: () -> Void = {}
    @Environment(SystemStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
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
                        row("Memory", Fmt.bytes(s.memory.used), values: store.memUsed.values, color: theme.memApp)
                    case .network:
                        row("Network", "↓ \(Fmt.rate(s.network.rateIn))  ↑ \(Fmt.rate(s.network.rateOut))",
                            values: store.netIn.values, color: theme.netIn, maxValue: 0)
                    case .gpu:
                        if let g = s.gpu { row("GPU", Fmt.percent(g.utilization), values: store.gpu.values, color: theme.gpu) }
                    default: EmptyView()
                    }
                }

            } else {
                ProgressView()
            }
            Divider()
            HStack {
                Button("Open Monitor") { openMonitor() }
                Spacer()
                Button("Settings…") {
                    close()
                    NSApp.activate()
                    openSettings()
                }
                Button("Quit") { NSApp.terminate(nil) }
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 320)
        .environment(\.theme, theme)
        .onChange(of: store.section) { _, _ in
            // Clicking a top process navigates the main window; bring it forward.
            openMonitor()
        }
    }

    private func openMonitor() {
        close()
        // SwiftUI keeps the main window after it is closed; reopen that one when it exists.
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
        NSApp.activate()
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
