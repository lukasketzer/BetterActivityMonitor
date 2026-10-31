import SystemKit
import WidgetKit

struct VolumeInfo: Hashable {
    var name: String
    var total: UInt64
    var available: UInt64
    var usedFraction: Double { total == 0 ? 0 : 1 - Double(available) / Double(total) }
}

struct BatteryInfo: Hashable {
    var charge: Double
    var isCharging: Bool
    var isPluggedIn: Bool
    var minutesRemaining: Int?
    var health: Double?
    var cycleCount: Int?
    var isCharged = false
    /// W flowing into (+) or out of (−) the battery.
    var batteryWatts: Double?
    /// The charger's rating and what it negotiated.
    var adapterWatts: Int?
    var adapterVolts: Double?
    var adapterAmps: Double?
    /// W coming from the charger and W the Mac uses, right now.
    var powerIn: Double?
    var systemLoad: Double?
}

/// One reading of everything the widgets show. Plain values so placeholders don't need a sampler.
struct SystemEntry: TimelineEntry {
    var date: Date
    var cpu: Double
    /// Nil when no GPU reports statistics.
    var gpu: Double?
    var loadAverage: [Double]
    var memTotal: UInt64
    var memApp: UInt64
    var memWired: UInt64
    var memCompressed: UInt64
    var memCached: UInt64
    var swapUsed: UInt64
    var volumes: [VolumeInfo]
    var battery: BatteryInfo?
    var bootDate: Date

    var memUsed: UInt64 { memApp + memWired + memCompressed }
    var memFraction: Double { memTotal == 0 ? 0 : Double(memUsed) / Double(memTotal) }
    /// The startup disk, or the first volume.
    var mainVolume: VolumeInfo? { volumes.first }

    static func sample() -> SystemEntry {
        let cpu = QuickSample.cpu()
        let mem = QuickSample.memory()
        // Internal volumes first; the startup disk is mounted at "/".
        let volumes = QuickSample.volumes()
            .filter { $0.isInternal || $0.isRemovable || $0.path.hasPrefix("/Volumes/") }
            .sorted { ($0.path == "/" ? 0 : $0.isInternal ? 1 : 2, $0.name) < ($1.path == "/" ? 0 : $1.isInternal ? 1 : 2, $1.name) }
            .map { VolumeInfo(name: $0.name, total: $0.total, available: $0.available) }
        let battery = QuickSample.battery().map {
            BatteryInfo(charge: $0.charge, isCharging: $0.isCharging, isPluggedIn: $0.isPluggedIn,
                        minutesRemaining: $0.minutesRemaining, health: $0.health, cycleCount: $0.cycleCount,
                        isCharged: $0.isCharged, batteryWatts: $0.watts, adapterWatts: $0.adapterWatts,
                        adapterVolts: $0.adapterVoltage, adapterAmps: $0.adapterCurrent,
                        powerIn: $0.systemPowerIn, systemLoad: $0.systemLoad)
        }
        return SystemEntry(
            date: .now, cpu: cpu.total, gpu: QuickSample.gpu(), loadAverage: cpu.loadAverage,
            memTotal: mem.total, memApp: mem.app, memWired: mem.wired, memCompressed: mem.compressed,
            memCached: mem.cached, swapUsed: mem.swapUsed,
            volumes: volumes, battery: battery, bootDate: QuickSample.bootDate
        )
    }

    static let placeholder: SystemEntry = {
        let gb: UInt64 = 1 << 30
        return SystemEntry(
            date: .now, cpu: 0.23, gpu: 0.41, loadAverage: [2.1, 2.4, 2.6],
            memTotal: 32 * gb, memApp: 11 * gb, memWired: 3 * gb, memCompressed: 2 * gb, memCached: 9 * gb,
            swapUsed: 0,
            volumes: [VolumeInfo(name: "Macintosh HD", total: 994 * gb, available: 612 * gb)],
            battery: BatteryInfo(charge: 0.82, isCharging: true, isPluggedIn: true, minutesRemaining: 38,
                                 health: 0.97, cycleCount: 84, batteryWatts: 31.4, adapterWatts: 140,
                                 adapterVolts: 28, adapterAmps: 5, powerIn: 48.2, systemLoad: 16.8),
            bootDate: .now.addingTimeInterval(-3 * 86400 - 4 * 3600)
        )
    }()
}

/// Shared by all widgets: one fresh reading, refreshed every 15 minutes (WidgetKit's budget allows no more).
struct SystemProvider: TimelineProvider {
    func placeholder(in context: Context) -> SystemEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (SystemEntry) -> Void) {
        completion(context.isPreview ? .placeholder : .sample())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SystemEntry>) -> Void) {
        let entry = SystemEntry.sample()
        HistoryStore.record(entry)
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
}
