// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexUsageMonitor",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CodexUsageMonitor", targets: ["CodexUsageMonitor"])
    ],
    targets: [
        .target(
            name: "CodexUsageMonitorCore",
            path: "Sources/CodexUsageMonitorCore"
        ),
        .executableTarget(
            name: "CodexUsageMonitor",
            dependencies: ["CodexUsageMonitorCore"],
            path: "Sources/CodexUsageMonitor"
        ),
        .executableTarget(
            name: "CodexUsageMonitorTests",
            dependencies: ["CodexUsageMonitorCore"],
            path: "Tests/CodexUsageMonitorTests"
        )
    ]
)
