// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ActivityManagerReloaded",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ActivityManagerReloaded", targets: ["ActivityManagerReloaded"]),
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
            name: "ActivityManagerReloaded",
            dependencies: ["SystemKit"]
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
