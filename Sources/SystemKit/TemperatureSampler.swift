import Foundation

/// Temperatures and fan speeds. SMC keys are enumerated once; each refresh reads only a small set of
/// representative CPU/GPU keys unless `detailed` is on (the Sensors page is open).
final class TemperatureSampler {
    private struct Key {
        var code: UInt32
        var name: String
        var info: SMC.KeyInfo
        var category: SensorCategory
    }

    var detailed = false

    private let smc = SMC()
    private lazy var hid = HIDSensorSampler()
    private var keys: [Key] = []
    private var routine: [Key] = []
    private var fanKeys: [(SMC.KeyInfo, UInt32)] = []
    private var enumerated = false
    private var last: [SensorReading] = []
    private var lastFans: [Double] = []
    private var lastRead: Date?
    private var lastWasDetailed = false

    private static let routineInterval: TimeInterval = 3
    private static let detailedInterval: TimeInterval = 5
    private static let routineKeysPerCategory = 6

    func sample() -> (sensors: [SensorReading], fans: [Double]) {
        let now = Date()
        let interval = detailed ? Self.detailedInterval : Self.routineInterval
        let modeChanged = detailed && !lastWasDetailed
        if !modeChanged, let lastRead, now.timeIntervalSince(lastRead) < interval { return (last, lastFans) }
        lastRead = now
        lastWasDetailed = detailed

        guard let smc else {
            last = hid.sample()
            return (last, [])
        }
        if !enumerated { enumerate(smc) }
        if keys.isEmpty {
            last = hid.sample()
            return (last, [])
        }

        let set = detailed ? keys : routine
        last = set.compactMap { key in
            guard let v = smc.value(key.code, key.info), v > 5, v < 130 else { return nil }
            return SensorReading(name: key.name, celsius: v, category: key.category)
        }
        lastFans = fanKeys.compactMap { smc.value($0.1, $0.0) }
        return (last, lastFans)
    }

    private func enumerate(_ smc: SMC) {
        enumerated = true
        var found: [(Key, Double)] = []
        for index in 0..<smc.keyCount {
            guard let code = smc.key(at: index) else { continue }
            let name = SMC.name(code)
            guard name.hasPrefix("T"), let info = smc.info(code),
                  ["flt ", "sp78"].contains(SMC.name(info.type)),
                  let value = smc.value(code, info), value > 5, value < 130,
                  value != 40 else { continue }  // exact 40.0 °C keys are unpopulated placeholders
            found.append((Key(code: code, name: name, info: info, category: Self.category(name)), value))
        }
        keys = found.map(\.0).sorted { $0.name < $1.name }
        // Routine set: the hottest keys of each CPU/GPU family track load best.
        routine = [SensorCategory.cpu, .gpu, .battery, .storage].flatMap { category in
            found.filter { $0.0.category == category }.sorted { $0.1 > $1.1 }
                .prefix(category == .cpu || category == .gpu ? Self.routineKeysPerCategory : 1).map(\.0)
        }

        let fanCount = SMC.code("FNum")
        if let info = smc.info(fanCount), let n = smc.value(fanCount, info) {
            fanKeys = (0..<Int(n)).compactMap { i in
                let code = SMC.code("F\(i)Ac")
                return smc.info(code).map { ($0, code) }
            }
        }
    }

    /// Apple Silicon SMC naming: Tp = performance cores, Te = efficiency cores, Tg = GPU,
    /// TB = battery, TH = SSD. Intel: TC = CPU, TG = GPU.
    private static func category(_ name: String) -> SensorCategory {
        switch name.prefix(2) {
        case "Tp", "Te", "TC": .cpu
        case "Tg", "TG": .gpu
        case "TB": .battery
        case "TH", "TN": .storage
        default: .other
        }
    }
}
