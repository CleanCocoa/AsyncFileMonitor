// swift-tools-version: 6.1
import PackageDescription

let package = Package(
	name: "AsyncFileMonitor",
	platforms: [
		.macOS(.v15)
	],
	products: [
		.library(name: "AsyncFileMonitor", targets: ["AsyncFileMonitor"])
	],
	dependencies: [
		.package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),
		.package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0"),
	],
	targets: [
		.target(
			name: "AsyncFileMonitor",
			dependencies: [
				.product(name: "OrderedCollections", package: "swift-collections")
			],
			exclude: []
		),
		.executableTarget(
			name: "watch",
			dependencies: ["AsyncFileMonitor"],
			path: "Sources/watch"
		),
		.testTarget(
			name: "AsyncFileMonitorTests",
			dependencies: ["AsyncFileMonitor"]
		),
		.testTarget(
			name: "RaceConditionTests",
			dependencies: ["AsyncFileMonitor"],
			path: "Tests/RaceConditionTests",
			exclude: ["README.md"]
		),
	]
)
