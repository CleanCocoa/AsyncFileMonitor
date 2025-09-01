// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "AsyncFileMonitor",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "AsyncFileMonitor", targets: ["AsyncFileMonitor"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "AsyncFileMonitor",
            dependencies: [],
            exclude: []
        ),
        .testTarget(
            name: "AsyncFileMonitorTests",
            dependencies: ["AsyncFileMonitor"]
        )
    ]
)
