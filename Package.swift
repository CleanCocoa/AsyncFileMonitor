// swift-tools-version: 6.1
import PackageDescription

let package = Package(
	name: "AsyncFileMonitor",
	platforms: [
		.macOS(.v15)
	],
	products: [
		.library(name: "AsyncFileMonitor", targets: ["AsyncFileMonitor"]),
		.library(name: "AsyncFileMonitorLinux", targets: ["AsyncFileMonitorLinux"]),
	],
	dependencies: [
		.package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),
		.package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0"),
	],
	targets: [
		// FSEvents-specific implementation (macOS only)
		.target(
			name: "AsyncFileMonitorFSEvents",
			dependencies: [
				.product(name: "Collections", package: "swift-collections")
			],
			path: "Sources/AsyncFileMonitor"
		),

		// Cross-platform AsyncFileMonitor API
		.target(
			name: "AsyncFileMonitor",
			dependencies: [
				.target(name: "AsyncFileMonitorFSEvents", condition: .when(platforms: [.macOS])),
				.target(name: "AsyncFileMonitorLinux", condition: .when(platforms: [.linux])),
			],
			path: "Sources/AsyncFileMonitorAPI"
		),

		// Linux libuv system library wrapper
		.systemLibrary(
			name: "Clibuv",
			pkgConfig: "libuv",
			providers: [
				.apt(["libuv1-dev"]),
				.yum(["libuv-devel"]),
			]
		),

		// Linux-specific file monitoring implementation
		.target(
			name: "AsyncFileMonitorLinux",
			dependencies: [
				"Clibuv",
				.product(name: "Collections", package: "swift-collections"),
			]
		),

		// Cross-platform CLI tool
		.executableTarget(
			name: "watch",
			dependencies: ["AsyncFileMonitor"],
			path: "Sources/watch"
		),

		// macOS tests
		.testTarget(
			name: "AsyncFileMonitorTests",
			dependencies: ["AsyncFileMonitor"]
		),
		// Temporarily disabled - need to update for new architecture
		// .testTarget(
		// 	name: "RaceConditionTests",
		// 	dependencies: ["AsyncFileMonitorFSEvents"],
		// 	path: "Tests/RaceConditionTests",
		// 	exclude: ["README.md"]
		// ),

		// Linux-specific tests
		.testTarget(
			name: "AsyncFileMonitorLinuxTests",
			dependencies: ["AsyncFileMonitorLinux"]
		),
	]
)
