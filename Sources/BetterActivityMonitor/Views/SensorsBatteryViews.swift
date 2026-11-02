import SwiftUI
import SystemKit

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
    /// Comma-separated raw values of the sensor categories whose lists are expanded. Lists start collapsed.
    @AppStorage(SettingsKey.sensorsExpanded) private var expandedCategories = ""

    private func expanded(_ category: SensorCategory) -> Binding<Bool> {
        Binding {
            expandedCategories.split(separator: ",").contains { $0 == category.rawValue }
        } set: { isExpanded in
            var set = Set(expandedCategories.split(separator: ",").map(String.init))
            if isExpanded { set.insert(category.rawValue) } else { set.remove(category.rawValue) }
            expandedCategories = set.sorted().joined(separator: ",")
        }
    }

    var body: some View {
        DetailPage {
            VStack(alignment: .leading, spacing: 16) {
                let groups = SensorGroup.make(store.snapshot?.sensors ?? [])
                if groups.isEmpty {
                    EmptyState(title: "No Temperature Sensors", symbol: "thermometer.slash",
                               message: "This Mac doesn't expose temperature sensors to apps.")
                } else {
                    StatStrip {
                        if let hottest = (store.snapshot?.sensors ?? []).max(by: { $0.celsius < $1.celsius }) {
                            BigStat(title: "Hottest · \(hottest.name)", value: Fmt.temperature(hottest.celsius, fahrenheit: fahrenheit),
                                    color: temperatureColor(hottest.celsius, theme))
                        }
                        ForEach(groups) { group in
                            BigStat(title: "\(group.category.rawValue) max", value: Fmt.temperature(group.max, fahrenheit: fahrenheit))
                        }
                        Spacer()
                    }
                    VStack(spacing: 10) {
                        ForEach(groups) { group in
                            Panel(group.category.rawValue, symbol: symbol(group.category), expanded: expanded(group.category)) {
                                Text("avg \(Fmt.temperature(group.average, fahrenheit: fahrenheit)) · max \(Fmt.temperature(group.max, fahrenheit: fahrenheit))")
                                    .monospacedDigit()
                            } content: {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 28, alignment: .top)], spacing: 5) {
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
