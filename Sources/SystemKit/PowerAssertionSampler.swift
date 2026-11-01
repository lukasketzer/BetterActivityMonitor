import Foundation
import IOKit.pwr_mgt

/// Which processes hold power assertions (keep the Mac or its display awake). Cached for a few seconds:
/// assertions change rarely and the call walks every one in the system.
final class PowerAssertionSampler {
    private var cached: [pid_t: [PowerAssertion]] = [:]
    private var lastRead: Date?
    var minimumInterval: TimeInterval = 5

    func sample(now: Date = Date()) -> [pid_t: [PowerAssertion]] {
        if let lastRead, now.timeIntervalSince(lastRead) < minimumInterval { return cached }
        lastRead = now
        cached = Self.read()
        return cached
    }

    static func read() -> [pid_t: [PowerAssertion]] {
        var raw: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&raw) == kIOReturnSuccess,
              let byPID = raw?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return [:] }
        var result: [pid_t: [PowerAssertion]] = [:]
        for (pid, list) in byPID {
            result[pid.int32Value] = list.map(parse)
        }
        return result
    }

    static func parse(_ info: [String: Any]) -> PowerAssertion {
        PowerAssertion(type: info[kIOPMAssertionTypeKey] as? String ?? "",
                       name: info[kIOPMAssertionNameKey] as? String ?? "",
                       created: info["AssertStartWhen"] as? Date)
    }
}
