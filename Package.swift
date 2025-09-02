// swift-tools-version: 6.1
import PackageDescription

let package = Package(
	name: "AsyncFileMonitor",
	platforms: [
		.macOS(.v14)
	],
	products: [
		.library(name: "AsyncFileMonitor", targets: ["AsyncFileMonitor"])
	],
	dependencies: [
		.package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0")
	],
	targets: [
		.target(
			name: "AsyncFileMonitor",
			dependencies: [
				.product(name: "Collections", package: "swift-collections")
			],
			exclude: []
		),
		.testTarget(
			name: "AsyncFileMonitorTests",
			dependencies: ["AsyncFileMonitor"]
		),
	]
)
