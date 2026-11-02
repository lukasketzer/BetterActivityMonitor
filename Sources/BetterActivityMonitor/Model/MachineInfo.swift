import AppKit
import Foundation

/// Facts about this Mac that don't change while the app runs (the live numbers come from the snapshot).
struct MachineInfo {
    var user: String
    var host: String
    var os: String
    var kernel: String
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
            model: sysctlString("hw.model") ?? "Mac",
            shell: shell,
            displays: NSScreen.screens.map { screen in
                let scale = screen.backingScaleFactor
                let size = "\(Int(screen.frame.width * scale))×\(Int(screen.frame.height * scale))"
                return scale > 1 ? "\(size) @ \(Int(scale))x" : size
            })
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}
