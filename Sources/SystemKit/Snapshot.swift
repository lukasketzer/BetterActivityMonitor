import Foundation

/// Everything sampled in one tick. All rates are per second, all sizes in bytes.
public struct SystemSnapshot: Sendable {
    public var timestamp: Date
    public var interval: TimeInterval
    public var cpu: CPUStats
    public var memory: MemoryStats
    public var network: NetworkStats
    public var disks: DiskStats
    public var gpu: GPUStats?
    public var battery: BatteryStats?
    public var sensors: [SensorReading]
    /// Fan speeds in RPM.
    public var fans: [Double]
    public var processes: [ProcessEntry]
    /// Nil unless connection tracking is on (`SystemMonitor.setConnectionMode`).
    public var connections: ConnectionStats?
    /// Power assertions by process.
    public var powerAssertions: [pid_t: [PowerAssertion]] = [:]
}

// MARK: CPU

public struct CoreLoad: Sendable, Hashable {
    public var user: Double    // 0...1
    public var system: Double  // 0...1
    public var total: Double { user + system }
}

public enum CoreKind: String, Sendable {
    case performance = "P"
    case efficiency = "E"
    case standard = ""
}

public struct CPUStats: Sendable {
    public var user: Double    // 0...1, whole machine
    public var system: Double  // 0...1
    public var total: Double { user + system }
    public var cores: [CoreLoad]
    public var coreKinds: [CoreKind]
    public var loadAverage: [Double]  // 1, 5, 15 min
    public var uptime: TimeInterval
    public var model: String
    public var physicalCores: Int
    public var logicalCores: Int
    public var performanceCores: Int
    public var efficiencyCores: Int
    public var processCount: Int
    public var threadCount: Int
}

// MARK: Memory

public enum MemoryPressure: Int, Sendable {
    case normal = 1, warning = 2, critical = 4

    public var label: String {
        switch self {
        case .normal: "Normal"
        case .warning: "Warning"
        case .critical: "Critical"
        }
    }
}

public struct MemoryStats: Sendable {
    public var total: UInt64
    public var app: UInt64
    public var wired: UInt64
    public var compressed: UInt64
    public var cached: UInt64
    public var free: UInt64
    public var used: UInt64 { app + wired + compressed }
    public var usedFraction: Double { total == 0 ? 0 : Double(used) / Double(total) }
    public var swapTotal: UInt64
    public var swapUsed: UInt64
    public var pressure: MemoryPressure
    public var pageIns: UInt64
    public var pageOuts: UInt64
    public var pageInsPerSecond: Double
    public var pageOutsPerSecond: Double
    public var compressionsPerSecond: Double
}

// MARK: Network

public struct NetworkInterface: Sendable, Identifiable, Hashable {
    public var id: String { name }
    public var name: String          // BSD name, e.g. en0
    public var displayName: String   // e.g. Wi-Fi
    public var isUp: Bool
    public var isLoopback: Bool
    public var addresses: [String]
    public var bytesIn: UInt64
    public var bytesOut: UInt64
    public var packetsIn: UInt64
    public var packetsOut: UInt64
    public var errorsIn: UInt64
    public var errorsOut: UInt64
    public var rateIn: Double
    public var rateOut: Double
}

public struct NetworkStats: Sendable {
    public var interfaces: [NetworkInterface]
    /// Sum over non-loopback interfaces.
    public var rateIn: Double
    public var rateOut: Double
    public var totalIn: UInt64
    public var totalOut: UInt64
}

// MARK: Disks

public struct DiskDevice: Sendable, Identifiable, Hashable {
    public var id: String { bsdName }
    public var bsdName: String
    public var bytesRead: UInt64
    public var bytesWritten: UInt64
    public var readsPerSecond: Double
    public var writesPerSecond: Double
    public var readRate: Double
    public var writeRate: Double
}

public struct Volume: Sendable, Identifiable, Hashable {
    public var id: String { path }
    public var name: String
    public var path: String
    public var format: String
    public var total: UInt64
    public var available: UInt64
    public var isInternal: Bool
    public var isRemovable: Bool
    public var used: UInt64 { total > available ? total - available : 0 }
    public var usedFraction: Double { total == 0 ? 0 : Double(used) / Double(total) }
}

public struct DiskStats: Sendable {
    public var devices: [DiskDevice]
    public var volumes: [Volume]
    public var readRate: Double
    public var writeRate: Double
    public var totalRead: UInt64
    public var totalWritten: UInt64
}

extension DiskStats {
    /// The volume mounted at /, or the first one listed when that isn't found.
    public var startupVolume: Volume? { volumes.first { $0.path == "/" } ?? volumes.first }
}

// MARK: GPU / Battery / Sensors

public struct GPUStats: Sendable {
    public var name: String
    public var coreCount: Int?
    public var utilization: Double          // 0...1
    public var rendererUtilization: Double? // 0...1
    public var tilerUtilization: Double?    // 0...1
    public var memoryUsed: UInt64?
    public var memoryAllocated: UInt64?
}

public struct BatteryStats: Sendable {
    public var charge: Double              // 0...1
    public var isCharging: Bool
    public var isPluggedIn: Bool
    public var isCharged: Bool
    public var minutesRemaining: Int?      // to empty or to full
    public var cycleCount: Int?
    public var health: Double?             // max capacity / design capacity
    public var designCapacity: Int?        // mAh
    public var maxCapacity: Int?           // mAh
    public var temperature: Double?        // °C
    public var voltage: Double?            // V
    public var amperage: Double?           // A, negative when discharging
    public var watts: Double? { voltage.flatMap { v in amperage.map { v * $0 } } }
    public var adapterWatts: Int?
    public var adapterVoltage: Double?     // V the charger negotiated
    public var adapterCurrent: Double?     // A the charger can supply
    /// W coming in from the charger right now.
    public var systemPowerIn: Double?
    /// W the whole Mac is using right now.
    public var systemLoad: Double?
    public var condition: String?
}

public struct SensorReading: Sendable, Identifiable, Hashable {
    public var id: String { name }
    public var name: String
    public var celsius: Double
    public var category: SensorCategory
}

public enum SensorCategory: String, Sendable, CaseIterable {
    case cpu = "CPU"
    case gpu = "GPU"
    case battery = "Battery"
    case storage = "Storage"
    case other = "Other"
}

// MARK: Processes

public enum ProcessState: String, Sendable, Comparable {
    case running = "Running"
    case sleeping = "Sleeping"
    case stopped = "Stopped"
    case zombie = "Zombie"
    case idle = "Idle"
    case unknown = "—"

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct ProcessEntry: Sendable, Identifiable, Hashable {
    public var id: pid_t { pid }
    public var pid: pid_t
    public var ppid: pid_t
    public var uid: uid_t
    public var user: String
    public var name: String
    public var path: String
    public var state: ProcessState
    public var nice: Int
    public var startTime: Date
    /// False when the kernel refused task info (other users' processes without root).
    public var hasTaskInfo: Bool
    /// Percent of one core (can exceed 100, like Activity Monitor).
    public var cpu: Double
    public var cpuTime: TimeInterval
    /// Physical footprint — what Activity Monitor calls "Memory".
    public var memory: UInt64
    public var resident: UInt64
    public var threads: Int
    public var diskReadRate: Double
    public var diskWriteRate: Double
    public var diskReadTotal: UInt64
    public var diskWriteTotal: UInt64
    public var idleWakeupsPerSecond: Double
    /// Network bytes per second and since launch, from `nettop`; zero while connection tracking is off.
    public var netRateIn: Double = 0
    public var netRateOut: Double = 0
    public var netTotalIn: UInt64 = 0
    public var netTotalOut: UInt64 = 0
    /// Watts over the last tick, from the kernel's per-process energy counter (`ri_energy_nj`).
    public var power: Double = 0
    /// Joules since the process started.
    public var energyTotal: Double = 0
}

/// A power assertion: a process asking macOS not to sleep (the system, the display, or both).
public struct PowerAssertion: Sendable, Hashable {
    /// IOKit type, e.g. `PreventUserIdleSystemSleep`.
    public var type: String
    /// The reason the process gave, e.g. "Playing video".
    public var name: String
    public var created: Date?

    public init(type: String, name: String, created: Date?) {
        self.type = type
        self.name = name
        self.created = created
    }

    /// Short, user-facing description of what the assertion blocks.
    public var effect: String {
        switch type {
        case "PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion": "Keeps the display on"
        case "PreventUserIdleSystemSleep", "NoIdleSleepAssertion": "Prevents idle sleep"
        case "PreventSystemSleep": "Prevents sleep"
        case "PreventDiskIdle": "Keeps disks awake"
        case "UserIsActive": "Marks the user as active"
        case "BackgroundTask", "ApplePushServiceTask": "Background task"
        default: type
        }
    }

    /// Whether this keeps the Mac (or its display) awake, as opposed to bookkeeping assertions.
    public var preventsSleep: Bool {
        ["PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion", "PreventUserIdleSystemSleep",
         "NoIdleSleepAssertion", "PreventSystemSleep"].contains(type)
    }
}
