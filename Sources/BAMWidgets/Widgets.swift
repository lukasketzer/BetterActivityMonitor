import SwiftUI
import WidgetKit

@main
struct BAMWidgetBundle: WidgetBundle {
    var body: some Widget {
        OverviewWidget()
        StatsOverviewWidget()
        SystemRingsWidget()
        MetricGraphWidget()
        ActivityGraphsWidget()
        ActivityStatsWidget()
        MemoryWidget()
        StorageWidget()
        UptimeWidget()
        BatteryWidget()
    }
}

// MARK: Memory

struct MemoryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Memory", provider: SystemProvider()) { entry in
            MemoryWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Memory")
        .description("How much memory is in use and what's using it.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct MemoryWidgetView: View {
    var entry: SystemEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(title: "Memory", symbol: "memorychip", color: WidgetColor.memory)
            Spacer(minLength: 0)
            ValueWithUnit(number: WidgetFmt.gigabytes(entry.memUsed), unit: "GB", size: family == .systemSmall ? 30 : 34)
            Text("used of \(WidgetFmt.bytes(entry.memTotal))")
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            MemoryBar(entry: entry)
            if family == .systemMedium {
                HStack(spacing: 12) {
                    ForEach(entry.memoryParts, id: \.name) { name, value, color in
                        HStack(spacing: 4) {
                            Circle().fill(color).frame(width: 7, height: 7)
                            Text(name).foregroundStyle(.secondary)
                            Text(WidgetFmt.bytes(value)).monospacedDigit()
                        }
                    }
                }
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                HStack {
                    Text(entry.swapUsed > 0 ? "Swap \(WidgetFmt.bytes(entry.swapUsed))" : "No swap used")
                    Spacer()
                    UpdatedFooter(date: entry.date)
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .opensSection("memory")
    }
}

// MARK: Storage

struct StorageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Storage", provider: SystemProvider()) { entry in
            StorageWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Storage")
        .description("Free space on your disks.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct StorageWidgetView: View {
    var entry: SystemEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(title: "Storage", symbol: "internaldrive", color: WidgetColor.disk)
            Spacer(minLength: 0)
            if let main = entry.mainVolume, family == .systemSmall {
                BigValue(text: WidgetFmt.diskBytes(main.available), size: 28)
                Text("free on \(main.name)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                CapacityBar(fraction: main.usedFraction, color: WidgetColor.disk)
            } else if entry.volumes.isEmpty {
                Text("No disks").foregroundStyle(.secondary)
            } else {
                ForEach(entry.volumes.prefix(3), id: \.self) { volume in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(volume.name).fontWeight(.medium).lineLimit(1)
                            Spacer()
                            Text("\(WidgetFmt.diskBytes(volume.available)) free")
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                        .font(.caption)
                        CapacityBar(fraction: volume.usedFraction, color: WidgetColor.disk)
                    }
                }
            }
        }
        .opensSection("disks")
    }
}

// MARK: Uptime

struct UptimeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Uptime", provider: SystemProvider()) { entry in
            UptimeWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Uptime")
        .description("How long your Mac has been running, ticking live.")
        .supportedFamilies([.systemSmall])
    }
}

struct UptimeWidgetView: View {
    var entry: SystemEntry

    private var days: Int { Int(entry.date.timeIntervalSince(entry.bootDate)) / 86400 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetHeader(title: "Uptime", symbol: "clock", color: .orange)
            Spacer(minLength: 0)
            if days > 0 {
                Text(days == 1 ? "1 day" : "\(days) days")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
            }
            // A timer text keeps ticking without a timeline reload, like the Clock widgets.
            Text(entry.bootDate.addingTimeInterval(Double(days) * 86400), style: .timer)
                .font(.system(size: days > 0 ? 20 : 30, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(days > 0 ? .secondary : .primary)
            Spacer(minLength: 0)
            Text("Load \(entry.loadAverage.map { $0.formatted(.number.precision(.fractionLength(2))) }.joined(separator: " "))")
                .font(.caption2).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
        }
        .opensSection("cpu")
    }
}

// MARK: Battery

struct BatteryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Battery", provider: SystemProvider()) { entry in
            BatteryWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Battery")
        .description("Charge and time remaining. The medium size adds charger and power details.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct BatteryWidgetView: View {
    var entry: SystemEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let b = entry.battery {
                if family == .systemMedium {
                    HStack(spacing: 16) {
                        ring(b)
                        details(b)
                    }
                } else {
                    VStack(spacing: 6) {
                        ring(b)
                        Text(subtitle(b)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "powerplug.fill").font(.title).foregroundStyle(.secondary)
                    Text("No battery").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .opensSection("battery")
    }

    private func ring(_ b: BatteryInfo) -> some View {
        ZStack {
            Ring(fraction: b.charge, color: WidgetColor.battery, lineWidth: 10)
            VStack(spacing: 0) {
                Image(systemName: b.isCharging ? "bolt.fill" : b.isPluggedIn ? "powerplug.fill" : "laptopcomputer")
                    .font(.title3)
                    .foregroundStyle(WidgetColor.battery)
                    .widgetAccentable()
                Text(WidgetFmt.percent(b.charge))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// Like the Batteries widget's detail: what's happening, then the numbers behind it.
    private func details(_ b: BatteryInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(status(b)).font(.headline)
                Text(subtitle(b)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                if b.isPluggedIn {
                    if let w = b.adapterWatts, w > 0 {
                        stat("Charger", "\(w) W", detail: chargerDetail(b))
                    }
                    if let p = b.powerIn { stat("From charger", watts(p)) }
                    if let l = b.systemLoad { stat("Mac using", watts(l)) }
                    if b.isCharging, let w = b.batteryWatts, w > 0.1 { stat("Into battery", watts(w)) }
                } else {
                    if let l = b.systemLoad ?? b.batteryWatts.map(abs) { stat("Mac using", watts(l)) }
                    if let h = b.health { stat("Health", WidgetFmt.percent(h)) }
                    if let c = b.cycleCount { stat("Cycles", "\(c)") }
                }
            }
            .font(.caption)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stat(_ label: String, _ value: String, detail: String? = nil) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Text(value).fontWeight(.semibold).monospacedDigit()
                if let detail { Text(detail).foregroundStyle(.tertiary).monospacedDigit() }
            }
            .lineLimit(1)
        }
    }

    private func watts(_ value: Double) -> String { String(format: "%.1f W", value) }

    private func chargerDetail(_ b: BatteryInfo) -> String? {
        guard let v = b.adapterVolts, let a = b.adapterAmps, v > 0 else { return nil }
        return String(format: "%.0f V · %.1f A", v, a)
    }

    private func status(_ b: BatteryInfo) -> String {
        if b.isCharging { return "Charging" }
        if b.isPluggedIn { return b.isCharged || b.charge >= 0.99 ? "Fully Charged" : "On Power Adapter" }
        return "On Battery"
    }

    private func subtitle(_ b: BatteryInfo) -> String {
        if b.isCharging, let m = b.minutesRemaining { return "\(WidgetFmt.minutes(m)) until full" }
        if b.isPluggedIn { return b.charge >= 0.99 ? "Fully charged" : "On power adapter" }
        if let m = b.minutesRemaining { return "\(WidgetFmt.minutes(m)) left" }
        if let h = b.health { return "Health \(WidgetFmt.percent(h))" }
        return "On battery"
    }
}

#Preview("Memory", as: .systemMedium) { MemoryWidget() } timeline: { SystemEntry.placeholder }
#Preview("Storage", as: .systemMedium) { StorageWidget() } timeline: { SystemEntry.placeholder }
#Preview("Uptime", as: .systemSmall) { UptimeWidget() } timeline: { SystemEntry.placeholder }
#Preview("Battery", as: .systemSmall) { BatteryWidget() } timeline: { SystemEntry.placeholder }
#Preview("Battery", as: .systemMedium) { BatteryWidget() } timeline: { SystemEntry.placeholder }
