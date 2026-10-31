import SwiftUI
import SystemKit

/// A metric the menu bar item can show, as a ring or as a value.
enum MenuBarMetric: String, CaseIterable, Identifiable {
    case cpu, memory, gpu, disk, battery, temperature, network
    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .gpu: "GPU"
        case .disk: "Startup Disk"
        case .battery: "Battery"
        case .temperature: "CPU Temperature"
        case .network: "Network"
        }
    }

    /// Same symbols as the widget's `WidgetMetric`, so both read alike.
    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .gpu: "cube.transparent"
        case .disk: "internaldrive"
        case .battery: "battery.75percent"
        case .temperature: "thermometer.medium"
        case .network: "arrow.up.arrow.down"
        }
    }

    func color(_ theme: Theme) -> Color {
        switch self {
        case .cpu: theme.cpu
        case .memory: theme.memApp
        case .gpu: theme.gpu
        case .disk: theme.diskRead
        case .battery: theme.low
        case .temperature: theme.temperature
        case .network: theme.netIn
        }
    }

    /// Strings at least as wide as anything `reading` produces in `style`, so the item keeps its width as values change.
    func widestTexts(_ style: MenuBarStyle) -> [String] {
        switch (self, style) {
        case (.temperature, _): ["888°"]
        case (.network, _): MenuBarBytes.widestRates
        case (_, .rings), (_, .percent): ["100%"]
        case (.cpu, .absolute): ["88.8", "888"]
        case (.memory, .absolute), (.disk, .absolute): MenuBarBytes.widest
        // GPU memory and battery time aren't always known; the percentage stands in then.
        case (.gpu, .absolute): MenuBarBytes.widest + ["100%"]
        case (.battery, .absolute): ["88:88", "100%"]
        }
    }
}

/// What the menu bar draws for one metric right now.
struct MenuBarReading: Equatable {
    var metric: MenuBarMetric
    /// Ring fill, 0...1. Nil for network, which has no natural maximum.
    var fraction: Double?
    /// Percentage text; network has one line per direction.
    var lines: [String]
    /// Absolute-value text, e.g. memory in use; the percentage where there is none.
    var absolute: [String]

    func text(_ style: MenuBarStyle) -> [String] { style == .absolute ? absolute : lines }
}

/// Plain values the readings are built from; decoupled from `SystemSnapshot` so it is easy to test.
struct MenuBarInputs {
    var cpu: Double
    var memory: Double
    var gpu: Double?
    var disk: Double?
    var battery: Double?
    var temperature: Double?  // °C
    var netIn: Double
    var netOut: Double
    // Absolute values.
    var load: Double?          // 1-minute load average
    var memoryUsed: Double?    // bytes
    var diskUsed: Double?      // bytes
    var gpuMemory: Double?     // bytes
    var batteryMinutes: Int?   // to empty or to full

    init(cpu: Double, memory: Double, gpu: Double? = nil, disk: Double? = nil, battery: Double? = nil,
         temperature: Double? = nil, netIn: Double = 0, netOut: Double = 0, load: Double? = nil,
         memoryUsed: Double? = nil, diskUsed: Double? = nil, gpuMemory: Double? = nil, batteryMinutes: Int? = nil) {
        self.cpu = cpu
        self.memory = memory
        self.gpu = gpu
        self.disk = disk
        self.battery = battery
        self.temperature = temperature
        self.netIn = netIn
        self.netOut = netOut
        self.load = load
        self.memoryUsed = memoryUsed
        self.diskUsed = diskUsed
        self.gpuMemory = gpuMemory
        self.batteryMinutes = batteryMinutes
    }

    @MainActor init(_ s: SystemSnapshot, temperature: Double?) {
        let root = s.disks.volumes.first { $0.path == "/" }
        self.init(cpu: s.cpu.total, memory: s.memory.usedFraction, gpu: s.gpu?.utilization,
                  disk: root?.usedFraction, battery: s.battery?.charge,
                  temperature: temperature, netIn: s.network.rateIn, netOut: s.network.rateOut,
                  load: s.cpu.loadAverage.first, memoryUsed: Double(s.memory.used), diskUsed: root.map { Double($0.used) },
                  gpuMemory: s.gpu?.memoryUsed.map(Double.init), batteryMinutes: s.battery?.minutesRemaining)
    }

    /// Nil when this Mac can't provide the metric (no battery on a desktop, no GPU or temperature sample).
    func reading(_ metric: MenuBarMetric, fahrenheit: Bool) -> MenuBarReading? {
        func percent(_ f: Double, absolute: String? = nil) -> MenuBarReading {
            let f = min(max(f, 0), 1)
            let text = Fmt.percent(f, digits: 0)
            return MenuBarReading(metric: metric, fraction: f, lines: [text], absolute: [absolute ?? text])
        }
        switch metric {
        case .cpu: return percent(cpu, absolute: load.map(MenuBarBytes.load))
        case .memory: return percent(memory, absolute: memoryUsed.map(MenuBarBytes.format))
        case .gpu: return gpu.map { percent($0, absolute: gpuMemory.map(MenuBarBytes.format)) }
        case .disk: return disk.map { percent($0, absolute: diskUsed.map(MenuBarBytes.format)) }
        case .battery:
            return battery.map { percent($0, absolute: batteryMinutes.map { String(format: "%d:%02d", $0 / 60, $0 % 60) }) }
        case .temperature:
            return temperature.map { c in
                let text = String(format: "%.0f°", fahrenheit ? c * 9 / 5 + 32 : c)
                return MenuBarReading(metric: metric, fraction: min(max(c / 100, 0), 1), lines: [text], absolute: [text])
            }
        case .network:
            let lines = ["↓" + MenuBarBytes.format(netIn), "↑" + MenuBarBytes.format(netOut)]
            return MenuBarReading(metric: metric, fraction: nil, lines: lines, absolute: lines)
        }
    }
}

/// Short sizes and rates like "512B", "1.2K", "48K", "3.4M": at most four characters, so they fit the menu bar.
enum MenuBarBytes {
    private static let units = ["B", "K", "M", "G", "T"]
    /// Every shape `format` can produce, with the widest digit.
    static let widest = units.flatMap { ["888\($0)", "8.8\($0)"] }
    static let widestRates = ["↓", "↑"].flatMap { arrow in widest.map { arrow + $0 } }

    /// Load average with one decimal below 100, like `uptime`.
    static func load(_ value: Double) -> String {
        String(format: value < 99.95 ? "%.1f" : "%.0f", max(value, 0))
    }

    static func format(_ bytes: Double) -> String {
        var v = max(bytes, 0)
        var unit = 0
        // Round first so 1023.9 shows as "1.0K", never "1024B".
        while v.rounded() >= 1000, unit < units.count - 1 {
            v /= 1024
            unit += 1
        }
        if v < 9.95, unit > 0 { return String(format: "%.1f%@", v, units[unit]) }
        return String(format: "%.0f%@", v, units[unit])
    }
}

enum MenuBarStyle: String, CaseIterable, Identifiable {
    // "values" is what earlier versions stored for the percentage style.
    case rings, percent = "values", absolute
    var id: String { rawValue }
    var label: String {
        switch self {
        case .rings: "Rings"
        case .percent: "Percentages"
        case .absolute: "Absolute Values"
        }
    }
}

/// One row of the menu bar settings list: a metric and whether it is shown. The array order is the display order.
struct MenuBarEntry: Hashable, Identifiable {
    var metric: MenuBarMetric
    var enabled: Bool
    var id: MenuBarMetric { metric }
}

/// The ordered list `@AppStorage` keeps as a short string like "cpu,memory,-gpu,-disk" ("-" = hidden).
struct MenuBarItems: RawRepresentable, Equatable {
    var entries: [MenuBarEntry]

    static let defaultEnabled: Set<MenuBarMetric> = [.cpu, .memory]
    static let `default` = MenuBarItems(entries: MenuBarMetric.allCases.map {
        MenuBarEntry(metric: $0, enabled: defaultEnabled.contains($0))
    })

    init(entries: [MenuBarEntry]) { self.entries = Self.normalized(entries) }

    init?(rawValue: String) {
        let entries = rawValue.split(separator: ",").compactMap { part -> MenuBarEntry? in
            let hidden = part.hasPrefix("-")
            return MenuBarMetric(rawValue: String(hidden ? part.dropFirst() : part)).map { MenuBarEntry(metric: $0, enabled: !hidden) }
        }
        self.init(entries: entries)
    }

    var rawValue: String {
        entries.map { ($0.enabled ? "" : "-") + $0.metric.rawValue }.joined(separator: ",")
    }

    var enabled: [MenuBarMetric] { entries.filter(\.enabled).map(\.metric) }

    /// Drops duplicates and appends metrics added in later versions (hidden), keeping the stored order.
    private static func normalized(_ entries: [MenuBarEntry]) -> [MenuBarEntry] {
        var seen = Set<MenuBarMetric>()
        var result = entries.filter { seen.insert($0.metric).inserted }
        for metric in MenuBarMetric.allCases where !seen.contains(metric) {
            result.append(MenuBarEntry(metric: metric, enabled: false))
        }
        return result
    }

    /// The list for users of the earlier CPU / Memory / Network toggles.
    static func migrated(cpu: Bool, memory: Bool, network: Bool) -> MenuBarItems {
        var items = MenuBarItems.default
        for i in items.entries.indices {
            switch items.entries[i].metric {
            case .cpu: items.entries[i].enabled = cpu
            case .memory: items.entries[i].enabled = memory
            case .network: items.entries[i].enabled = network
            default: break
            }
        }
        return items
    }
}
