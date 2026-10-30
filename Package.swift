// swift-tools-version: 5.10
import Foundation
import PackageDescription

/// SwiftPM stamps the binary's SDK version as the deployment target (14.0), and AppKit then draws the
/// legacy macOS 14 window chrome (old traffic lights, toolbar and sidebar) even on newer systems.
/// Linking with the real SDK version gives `swift build`/`swift run` the current system design while
/// still running on macOS 14. Nil when xcrun can't answer; the build then keeps SwiftPM's default.
let sdkVersion: String? = {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["--show-sdk-version"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return nil }
    process.waitUntilExit()
    let version = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return process.terminationStatus == 0 && !version.isEmpty ? version : nil
}()

let currentDesign: [LinkerSetting] = sdkVersion.map {
    [.unsafeFlags(["-Xlinker", "-platform_version", "-Xlinker", "macos", "-Xlinker", "14.0", "-Xlinker", $0])]
} ?? []

let package = Package(
    name: "BetterActivityMonitor",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "BetterActivityMonitor", targets: ["BetterActivityMonitor"]),
        .library(name: "SystemKit", targets: ["SystemKit"]),
    ],
    targets: [
        .target(
            name: "SystemKit",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("SystemConfiguration"),
            ]
        ),
        .executableTarget(
            name: "BetterActivityMonitor",
            dependencies: ["SystemKit"],
            linkerSettings: currentDesign
        ),
        .executableTarget(
            name: "sysbench",
            dependencies: ["SystemKit"]
        ),
        .testTarget(
            name: "SystemKitTests",
            dependencies: ["SystemKit"]
        ),
        // Launches the bundled app and checks its CPU use per screen. Opt-in: BAM_APP_PERF=1 (see README).
        .testTarget(
            name: "AppPerformanceTests"
        ),
    ]
)
