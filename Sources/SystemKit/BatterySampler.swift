import Foundation
import IOKit
import IOKit.ps

final class BatterySampler {
    private var cached: BatteryStats?
    private var lastRead: Date?

    func sample() -> BatteryStats? {
        let now = Date()
        if let lastRead, now.timeIntervalSince(lastRead) < 5 { return cached }
        lastRead = now
        cached = read()
        return cached
    }

    private func read() -> BatteryStats? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        let source = list.lazy
            .compactMap { IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any] }
            .first { ($0[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType }
        guard let source else { return nil }

        let current = source.number(kIOPSCurrentCapacityKey) ?? 0
        let max = source.number(kIOPSMaxCapacityKey) ?? 100
        let isCharging = source[kIOPSIsChargingKey] as? Bool ?? false
        let pluggedIn = (source[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        let timeKey = isCharging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
        let minutes = source.int(timeKey).flatMap { $0 > 0 ? $0 : nil }

        var stats = BatteryStats(
            charge: max > 0 ? current / max : 0,
            isCharging: isCharging, isPluggedIn: pluggedIn,
            isCharged: source[kIOPSIsChargedKey] as? Bool ?? false,
            minutesRemaining: minutes,
            condition: source[kIOPSBatteryHealthKey] as? String
        )

        IORegistry.forEachService(matching: "AppleSmartBattery") { _, top in
            // Newer firmware nests most values under "BatteryData".
            let props = top.merging(top["BatteryData"] as? [String: Any] ?? [:]) { current, _ in current }
            stats.cycleCount = props.int("CycleCount")
            stats.designCapacity = props.int("DesignCapacity")
            stats.maxCapacity = props.int("AppleRawMaxCapacity") ?? props.int("FullChargeCapacity") ?? props.int("NominalChargeCapacity")
            if let design = stats.designCapacity, let maxCap = stats.maxCapacity, design > 0 {
                stats.health = Double(maxCap) / Double(design)
            }
            if let t = props.number("Temperature") ?? props.number("VirtualTemperature") { stats.temperature = t / 100 }
            if let v = props.number("Voltage") { stats.voltage = v / 1000 }
            if let a = props["InstantAmperage"] as? NSNumber ?? props["Amperage"] as? NSNumber {
                stats.amperage = Double(a.int64Value) / 1000
            }
            if let adapter = props["AdapterDetails"] as? [String: Any] { stats.adapterWatts = adapter.int("Watts") }
        }
        return stats
    }
}

extension BatteryStats {
    init(charge: Double, isCharging: Bool, isPluggedIn: Bool, isCharged: Bool, minutesRemaining: Int?, condition: String?) {
        self.init(charge: charge, isCharging: isCharging, isPluggedIn: isPluggedIn, isCharged: isCharged,
                  minutesRemaining: minutesRemaining, cycleCount: nil, health: nil, designCapacity: nil,
                  maxCapacity: nil, temperature: nil, voltage: nil, amperage: nil, adapterWatts: nil,
                  condition: condition)
    }
}
