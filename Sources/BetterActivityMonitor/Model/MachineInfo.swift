import AppKit
import Foundation
import IOKit

/// Facts about this Mac that don't change while the app runs (the live numbers come from the snapshot).
struct MachineInfo {
    var user: String
    var host: String
    var os: String
    var kernel: String
    /// Marketing name, e.g. "MacBook Pro (16-inch, Nov 2024)"; nil when the registry doesn't have one.
    var productName: String?
    /// Raw model identifier, e.g. "Mac16,5".
    var model: String
    var shell: String
    var displays: [String]

    static let current = MachineInfo.read()

    private static func read() -> MachineInfo {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        var os = "macOS \(v.majorVersion).\(v.minorVersion)"
        if v.patchVersion > 0 { os += ".\(v.patchVersion)" }
        if let build = sysctlString("kern.osversion") { os += " (\(build))" }
        let shell = getpwuid(getuid()).flatMap { String(cString: $0.pointee.pw_shell) }
            .map { ($0 as NSString).lastPathComponent } ?? "unknown"
        return MachineInfo(
            user: NSUserName(),
            host: Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
            os: os,
            kernel: sysctlString("kern.osrelease").map { "Darwin \($0)" } ?? "Darwin",
            productName: productName(),
            model: sysctlString("hw.model") ?? "Mac",
            shell: shell,
            displays: NSScreen.screens.map { screen in
                let scale = screen.backingScaleFactor
                let size = "\(Int(screen.frame.width * scale))×\(Int(screen.frame.height * scale))"
                return scale > 1 ? "\(size) @ \(Int(scale))x" : size
            })
    }

    /// When the Mac last booted (`kern.boottime`).
    static var bootTime: Date? { sysctlDate("kern.boottime") }

    /// When the Mac last woke from sleep, or nil if it hasn't slept since booting.
    static var lastWake: Date? {
        guard let wake = sysctlDate("kern.waketime"), let boot = bootTime, wake > boot else { return nil }
        return wake
    }

    /// Apple silicon Macs carry the "About This Mac" name in the device tree's `/product` node.
    private static func productName() -> String? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        guard let data = IORegistryEntryCreateCFProperty(entry, "product-name" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Data else { return nil }
        let name = String(decoding: data.prefix { $0 != 0 }, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    private static func sysctlDate(_ name: String) -> Date? {
        var value = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0, value.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(value.tv_sec) + TimeInterval(value.tv_usec) / 1_000_000)
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}
