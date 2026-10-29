import Foundation

/// Fallback temperature source via the private IOHIDEventSystem API. ~8 ms per sensor, so only used
/// when the SMC is unavailable. Resolved with dlsym so a missing symbol means "no sensors", not a crash.
final class HIDSensorSampler {
    private typealias CreateClient = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatching = @convention(c) (AnyObject, CFDictionary) -> Int32
    private typealias CopyServices = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias CopyProperty = @convention(c) (AnyObject, CFString) -> Unmanaged<AnyObject>?
    private typealias CopyEvent = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias GetFloat = @convention(c) (AnyObject, Int32) -> Double

    private static let temperatureEventType: Int64 = 15  // kIOHIDEventTypeTemperature

    private var client: AnyObject?
    private var copyServices: CopyServices?
    private var copyProperty: CopyProperty?
    private var copyEvent: CopyEvent?
    private var getFloat: GetFloat?

    // Sensor reads go through the SMC and are slow; temperatures also change slowly.
    private var services: [AnyObject] = []
    private var names: [String] = []
    private var servicesLoaded: Date?
    private var lastReadings: [SensorReading] = []
    private var lastRead: Date?
    private let minimumInterval: TimeInterval = 3

    init() {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY),
              let create = dlsym(handle, "IOHIDEventSystemClientCreate"),
              let setMatching = dlsym(handle, "IOHIDEventSystemClientSetMatching"),
              let services = dlsym(handle, "IOHIDEventSystemClientCopyServices"),
              let property = dlsym(handle, "IOHIDServiceClientCopyProperty"),
              let event = dlsym(handle, "IOHIDServiceClientCopyEvent"),
              let float = dlsym(handle, "IOHIDEventGetFloatValue") else { return }

        let createFn = unsafeBitCast(create, to: CreateClient.self)
        guard let client = createFn(kCFAllocatorDefault)?.takeRetainedValue() else { return }
        // Apple vendor page 0xff00, usage 5 = temperature sensors.
        let matching = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary
        _ = unsafeBitCast(setMatching, to: SetMatching.self)(client, matching)

        self.client = client
        copyServices = unsafeBitCast(services, to: CopyServices.self)
        copyProperty = unsafeBitCast(property, to: CopyProperty.self)
        copyEvent = unsafeBitCast(event, to: CopyEvent.self)
        getFloat = unsafeBitCast(float, to: GetFloat.self)
    }

    func sample() -> [SensorReading] {
        let now = Date()
        if let lastRead, now.timeIntervalSince(lastRead) < minimumInterval { return lastReadings }
        guard let client, let copyServices, let copyProperty, let copyEvent, let getFloat else { return [] }

        if servicesLoaded.map({ now.timeIntervalSince($0) > 60 }) ?? true,
           let list = copyServices(client)?.takeRetainedValue() as [AnyObject]? {
            services = []
            names = []
            for service in list {
                guard let name = copyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String else { continue }
                services.append(service)
                names.append(name)
            }
            servicesLoaded = now
        }

        let field = Int32(truncatingIfNeeded: Self.temperatureEventType << 16)
        var readings: [String: SensorReading] = [:]
        for (service, name) in zip(services, names) {
            guard let event = copyEvent(service, Self.temperatureEventType, 0, 0)?.takeRetainedValue() else { continue }
            let value = getFloat(event, field)
            guard value > 0, value < 150 else { continue }
            readings[name] = SensorReading(name: name, celsius: value, category: Self.category(for: name))
        }
        lastReadings = readings.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        lastRead = now
        return lastReadings
    }

    private static func category(for name: String) -> SensorCategory {
        let n = name.lowercased()
        if n.contains("tdie") || n.contains("cpu") || n.contains("soc") || n.contains("pmu") && n.contains("tdev") { return .cpu }
        if n.contains("gpu") { return .gpu }
        if n.contains("battery") || n.contains("gas gauge") { return .battery }
        if n.contains("nand") || n.contains("ssd") { return .storage }
        return .other
    }
}
