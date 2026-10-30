import SwiftUI
import SystemKit

/// btop-style GPU box: utilization graph plus renderer/tiler load, memory and temperature.
struct GPUPanel: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.theme) private var theme
    @AppStorage(SettingsKey.fahrenheit) private var fahrenheit = false

    var body: some View {
        let g = store.snapshot?.gpu
        Panel("GPU", symbol: "cube.transparent", destination: .sensors) {
            if let g { Text(g.coreCount.map { "\($0) cores" } ?? g.name) }
        } content: {
            if let g {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(Fmt.percent(g.utilization, digits: 0))
                            .font(.system(size: 28, weight: .semibold).monospacedDigit())
                            .foregroundStyle(theme.meter(g.utilization))
                        Spacer(minLength: 4)
                        if let t = gpuTemperature {
                            Label(Fmt.temperature(t, fahrenheit: fahrenheit), systemImage: "thermometer.medium")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(temperatureColor(t, theme))
                        }
                    }
                    HistoryChart(series: [ChartSeries(name: "GPU", color: theme.gpu, history: store.gpu)],
                                 maxY: 1, showsYAxis: false) { Fmt.percent($0, digits: 0) }
                        .frame(minHeight: 40)
                    if let r = g.rendererUtilization { meterRow("Renderer", r, Fmt.percent(r, digits: 0)) }
                    if let t = g.tilerUtilization { meterRow("Tiler", t, Fmt.percent(t, digits: 0)) }
                    if let used = g.memoryUsed, let total = store.snapshot?.memory.total, total > 0 {
                        meterRow("Memory", Double(used) / Double(total), Fmt.bytes(used))
                    }
                }
            } else {
                Text("No GPU statistics available").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var gpuTemperature: Double? {
        store.snapshot?.sensors.filter { $0.category == .gpu }.map(\.celsius).max()
    }

    private func meterRow(_ label: String, _ fraction: Double, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label).foregroundStyle(.secondary).frame(width: 58, alignment: .leading)
            MeterBar(fraction: fraction, color: theme.gpu, height: 5)
            Text(value).monospacedDigit().frame(width: 58, alignment: .trailing)
        }
        .font(.caption)
        .lineLimit(1)
    }
}

struct SensorsPanel: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.theme) private var theme
    @AppStorage(SettingsKey.fahrenheit) private var fahrenheit = false

    var body: some View {
        Panel("Sensors", symbol: "thermometer.medium", destination: .sensors) {
            if let t = store.cpuTemperatureNow { Text("CPU \(Fmt.temperature(t, fahrenheit: fahrenheit))").monospacedDigit() }
        } content: {
            VStack(alignment: .leading, spacing: 6) {
                if store.cpuTemperature.points.count > 1 {
                    HistoryChart(series: [ChartSeries(name: "Hottest CPU die", color: theme.temperature, history: store.cpuTemperature)],
                                 maxY: nil, showsYAxis: false) { Fmt.temperature($0, fahrenheit: fahrenheit) }
                        .frame(minHeight: 40)
                }
                let groups = SensorGroup.make(store.snapshot?.sensors ?? [])
                ForEach(groups.prefix(4)) { group in
                    HStack {
                        Text(group.category.rawValue).foregroundStyle(.secondary)
                        Spacer()
                        Text(Fmt.temperature(group.max, fahrenheit: fahrenheit)).monospacedDigit()
                            .foregroundStyle(temperatureColor(group.max, theme))
                    }
                    .font(.caption)
                }
                if let fans = store.snapshot?.fans, !fans.isEmpty {
                    HStack {
                        Text("Fans").foregroundStyle(.secondary)
                        Spacer()
                        Text(fans.allSatisfy { $0 < 1 } ? "Off" : fans.map { "\(Int($0))" }.joined(separator: " / ") + " rpm").monospacedDigit()
                    }
                    .font(.caption)
                }
                if let b = store.snapshot?.battery {
                    HStack {
                        Image(systemName: batterySymbol(b)).foregroundStyle(b.charge < 0.2 ? theme.high : theme.low)
                        Text(Fmt.percent(b.charge, digits: 0)).monospacedDigit()
                        Spacer()
                        if let w = b.watts { Text(String(format: "%.1f W", abs(w))).monospacedDigit().foregroundStyle(.secondary) }
                    }
                    .font(.caption)
                }
                if groups.isEmpty && store.snapshot?.battery == nil {
                    Text("No sensors available").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct SensorGroup: Identifiable {
    var id: SensorCategory { category }
    var category: SensorCategory
    var sensors: [SensorReading]
    var max: Double { sensors.map(\.celsius).max() ?? 0 }
    var average: Double { sensors.isEmpty ? 0 : sensors.map(\.celsius).reduce(0, +) / Double(sensors.count) }

    static func make(_ readings: [SensorReading]) -> [SensorGroup] {
        SensorCategory.allCases.compactMap { category in
            let sensors = readings.filter { $0.category == category }
            return sensors.isEmpty ? nil : SensorGroup(category: category, sensors: sensors)
        }
    }
}

func temperatureColor(_ celsius: Double, _ theme: Theme) -> Color {
    theme.meter((celsius - 30) / 70)
}

func batterySymbol(_ b: BatteryStats) -> String {
    if b.isCharging { return "battery.100percent.bolt" }
    switch b.charge {
    case ..<0.13: return "battery.0percent"
    case ..<0.38: return "battery.25percent"
    case ..<0.63: return "battery.50percent"
    case ..<0.88: return "battery.75percent"
    default: return "battery.100percent"
    }
}

struct SensorsView: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.theme) private var theme
    @AppStorage(SettingsKey.fahrenheit) private var fahrenheit = false

    var body: some View {
        DetailPage {
            VStack(alignment: .leading, spacing: 16) {
                if let g = store.snapshot?.gpu {
                    StatStrip {
                        BigStat(title: "GPU", value: Fmt.percent(g.utilization), color: theme.gpu)
                        if let r = g.rendererUtilization { BigStat(title: "Renderer", value: Fmt.percent(r)) }
                        if let t = g.tilerUtilization { BigStat(title: "Tiler", value: Fmt.percent(t)) }
                        if let used = g.memoryUsed { BigStat(title: "GPU memory in use", value: Fmt.bytes(used)) }
                        Spacer()
                    }
                    Panel(g.coreCount.map { "\(g.name) · \($0)-core GPU" } ?? g.name, symbol: "cube.transparent") {
                        HistoryChart(series: [ChartSeries(name: "Utilization", color: theme.gpu, history: store.gpu)],
                                     maxY: 1) { Fmt.percent($0, digits: 0) }
                            .frame(height: 160)
                    }
                }

                if let fans = store.snapshot?.fans, !fans.isEmpty {
                    Panel("Fans", symbol: "fan") {
                        HStack(spacing: 28) {
                            ForEach(Array(fans.enumerated()), id: \.offset) { index, rpm in
                                BigStat(title: "Fan \(index + 1)", value: "\(Int(rpm)) rpm")
                            }
                            Spacer()
                        }
                    }
                }

                let groups = SensorGroup.make(store.snapshot?.sensors ?? [])
                if groups.isEmpty {
                    EmptyState(title: "No Temperature Sensors", symbol: "thermometer.slash",
                               message: "This Mac doesn't expose temperature sensors to apps.")
                } else {
                    if store.cpuTemperature.points.count > 1 {
                        Panel("CPU Temperature", symbol: "thermometer.medium") {
                            HistoryChart(series: [ChartSeries(name: "Hottest CPU die", color: theme.temperature, history: store.cpuTemperature)],
                                         maxY: nil) { Fmt.temperature($0, fahrenheit: fahrenheit) }
                                .frame(height: 140)
                        }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16, alignment: .top)], spacing: 16) {
                        ForEach(groups) { group in
                            Panel(group.category.rawValue, symbol: symbol(group.category)) {
                                Text("avg \(Fmt.temperature(group.average, fahrenheit: fahrenheit)) · max \(Fmt.temperature(group.max, fahrenheit: fahrenheit))")
                                    .monospacedDigit()
                            } content: {
                                VStack(spacing: 5) {
                                    ForEach(group.sensors) { sensor in
                                        HStack(spacing: 8) {
                                            Text(sensor.name).font(.callout).lineLimit(1)
                                            Spacer()
                                            MeterBar(fraction: (sensor.celsius - 20) / 80, color: temperatureColor(sensor.celsius, theme), height: 5)
                                                .frame(width: 60)
                                            Text(Fmt.temperature(sensor.celsius, fahrenheit: fahrenheit))
                                                .monospacedDigit().frame(width: 44, alignment: .trailing)
                                            Text("max \(Fmt.temperature(store.sensorMax[sensor.name] ?? sensor.celsius, fahrenheit: fahrenheit))")
                                                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                                                .frame(width: 64, alignment: .trailing)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .onAppear { store.setDetailedSensors(true) }
        .onDisappear { store.setDetailedSensors(false) }
    }

    private func symbol(_ category: SensorCategory) -> String {
        switch category {
        case .cpu: "cpu"
        case .gpu: "cube.transparent"
        case .battery: "battery.75percent"
        case .storage: "internaldrive"
        case .other: "thermometer.medium"
        }
    }
}

struct BatteryView: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.theme) private var theme
    @AppStorage(SettingsKey.fahrenheit) private var fahrenheit = false

    var body: some View {
        DetailPage {
            if let b = store.snapshot?.battery {
                VStack(alignment: .leading, spacing: 16) {
                    StatStrip {
                        Gauge(value: b.charge) {
                            Image(systemName: batterySymbol(b))
                        } currentValueLabel: {
                            Text(Fmt.percent(b.charge, digits: 0)).monospacedDigit()
                        }
                        .gaugeStyle(.accessoryCircularCapacity)
                        .tint(b.charge < 0.2 ? theme.high : theme.low)
                        .scaleEffect(1.4)
                        .frame(width: 80, height: 80)
                        BigStat(title: "Status", value: status(b))
                        if let minutes = b.minutesRemaining {
                            BigStat(title: b.isCharging ? "Until full" : "Remaining", value: Fmt.minutes(minutes))
                        }
                        if let w = b.watts { BigStat(title: b.isCharging ? "Charging power" : "Power draw", value: String(format: "%.1f W", abs(w)), color: theme.mid) }
                        if let h = b.health { BigStat(title: "Health", value: Fmt.percent(h, digits: 0), color: theme.meter(1 - h + 0.3)) }
                        Spacer()
                    }

                    Panel("Charge", symbol: "chart.xyaxis.line") {
                        HistoryChart(series: [ChartSeries(name: "Charge", color: theme.low, history: store.batteryCharge)],
                                     maxY: 1) { Fmt.percent($0, digits: 0) }
                            .frame(height: 120)
                    }
                    if store.batteryPower.points.count > 1 {
                        Panel("Power", symbol: "bolt") {
                            HistoryChart(series: [ChartSeries(name: "Watts", color: theme.mid, history: store.batteryPower)],
                                         maxY: nil) { String(format: "%.1f W", $0) }
                                .frame(height: 120)
                        }
                    }
                    Panel("Details", symbol: "info.circle") {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                            if let c = b.cycleCount { StatRow("Cycle count", "\(c)") }
                            if let max = b.maxCapacity, let design = b.designCapacity { StatRow("Capacity", "\(max) mAh of \(design) mAh design") }
                            if let condition = b.condition { StatRow("Condition", condition) }
                            if let v = b.voltage { StatRow("Voltage", String(format: "%.2f V", v)) }
                            if let a = b.amperage { StatRow("Current", String(format: "%.2f A", a)) }
                            if let t = b.temperature { StatRow("Temperature", Fmt.temperature(t, fahrenheit: fahrenheit)) }
                            if let w = b.adapterWatts, w > 0 { StatRow("Power adapter", "\(w) W") }
                        }
                    }
                }
                .padding()
            } else {
                EmptyState(title: "No Battery", symbol: "powerplug", message: "This Mac runs on AC power.")
                    .frame(minHeight: 400)
            }
        }
    }

    private func status(_ b: BatteryStats) -> String {
        if b.isCharged { return "Charged" }
        if b.isCharging { return "Charging" }
        return b.isPluggedIn ? "Plugged in" : "On battery"
    }
}
