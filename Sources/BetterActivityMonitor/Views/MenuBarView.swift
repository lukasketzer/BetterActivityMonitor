import SwiftUI

struct MenuBarLabel: View {
    var store: SystemStore
    @AppStorage(SettingsKey.menuBarShowsCPU) private var cpu = true
    @AppStorage(SettingsKey.menuBarShowsMemory) private var memory = true
    @AppStorage(SettingsKey.menuBarShowsNetwork) private var network = false

    var body: some View {
        if let s = store.snapshot {
            let parts = [
                cpu ? "CPU \(Fmt.percent(s.cpu.total, digits: 0))" : nil,
                memory ? "MEM \(Fmt.percent(s.memory.usedFraction, digits: 0))" : nil,
                network ? "↓\(Fmt.rate(s.network.rateIn))" : nil,
            ].compactMap { $0 }
            if parts.isEmpty {
                Image(systemName: "gauge.with.dots.needle.33percent")
            } else {
                Text(parts.joined(separator: "  ")).monospacedDigit()
            }
        } else {
            Image(systemName: "gauge.with.dots.needle.33percent")
        }
    }
}

struct MenuBarView: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @AppStorage(SettingsKey.theme) private var themeID = Theme.system.id

    var body: some View {
        let theme = Theme.named(themeID)
        VStack(alignment: .leading, spacing: 12) {
            if let s = store.snapshot {
                row("CPU", Fmt.percent(s.cpu.total), values: store.cpuTotal.values, color: theme.cpu)
                row("Memory", "\(Fmt.bytes(s.memory.used)) · \(s.memory.pressure.label)", values: store.memUsed.values, color: theme.memApp)
                row("Network", "↓ \(Fmt.rate(s.network.rateIn))  ↑ \(Fmt.rate(s.network.rateOut))",
                    values: store.netIn.values, color: theme.netIn, maxValue: 0)
                if let g = s.gpu { row("GPU", Fmt.percent(g.utilization), values: store.gpu.values, color: theme.gpu) }

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
