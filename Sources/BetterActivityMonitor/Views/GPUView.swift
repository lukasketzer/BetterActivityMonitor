import SwiftUI
import SystemKit

/// GPU load and memory. Temperatures of every component live on the Temperatures page.
struct GPUView: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.theme) private var theme
    @AppStorage(SettingsKey.fahrenheit) private var fahrenheit = false

    var body: some View {
        DetailPage {
            if let g = store.snapshot?.gpu {
                VStack(alignment: .leading, spacing: 16) {
                    StatStrip {
                        BigStat(title: "GPU", value: Fmt.percent(g.utilization), color: theme.gpu)
                        if let r = g.rendererUtilization { BigStat(title: "Renderer", value: Fmt.percent(r)) }
                        if let t = g.tilerUtilization { BigStat(title: "Tiler", value: Fmt.percent(t)) }
                        if let used = g.memoryUsed { BigStat(title: "Memory in use", value: Fmt.bytes(used)) }
                        if let alloc = g.memoryAllocated { BigStat(title: "Memory allocated", value: Fmt.bytes(alloc)) }
                        if let t = gpuTemperature {
                            BigStat(title: "Temperature", value: Fmt.temperature(t, fahrenheit: fahrenheit),
                                    color: temperatureColor(t, theme))
                        }
                        Spacer()
                    }
                    Panel(g.coreCount.map { "\(g.name) · \($0)-core GPU" } ?? g.name, symbol: "cube.transparent") {
                        HistoryChart(series: [ChartSeries(name: "Utilization", color: theme.gpu, history: store.gpu)],
                                     maxY: 1) { Fmt.percent($0, digits: 0) }
                            .frame(height: 200)
                    }
                }
                .padding()
            } else {
                EmptyState(title: "No GPU Data", symbol: "cube.transparent",
                           message: "This Mac doesn't report GPU statistics to apps.")
                    .frame(minHeight: 400)
            }
        }
    }

    private var gpuTemperature: Double? {
        store.snapshot?.sensors.filter { $0.category == .gpu }.map(\.celsius).max()
    }
}
