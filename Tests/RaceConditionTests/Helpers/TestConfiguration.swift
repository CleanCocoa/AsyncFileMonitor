//
// TestConfiguration.swift
// TestHelpers
//
// Shared test configuration system for consistent file system monitoring scenarios.
// This provides standard test cases that can be used across different execution modes
// (thread-safe, unsafe, AsyncFileMonitor, etc.) for fair comparisons.
//
// Reference: 20250904T105800
//

import Foundation

/// Standard test scenarios for file system monitoring
public struct FSMonitorTestScenario: Sendable {
	public let name: String
	public let fileCount: Int
	public let creationDelay: UInt64  // nanoseconds between file creation
	public let streamLatency: CFTimeInterval  // FSEventStream latency
	public let waitTime: UInt64  // nanoseconds to wait for events

	public init(
		name: String,
		fileCount: Int,
		creationDelay: UInt64,
		streamLatency: CFTimeInterval,
		waitTime: UInt64? = nil
	) {
		self.name = name
		self.fileCount = fileCount
		self.creationDelay = creationDelay
		self.streamLatency = streamLatency
		// Default wait time: max of (latency + 0.5s, 1.0s)
		self.waitTime = waitTime ?? UInt64(max(streamLatency + 0.5, 1.0) * 1_000_000_000)
	}
}

/// Standard test scenarios used across all file system monitoring tests
public enum StandardTestScenarios {
	/// Moderate load scenario - good for basic validation
	public static let moderateLoad = FSMonitorTestScenario(
		name: "moderate load",
		fileCount: 100,
		creationDelay: 8_000_000,  // 8ms delay
		streamLatency: 0.1
	)

	/// High stress scenario - minimal delays to stress concurrency
	public static let highStress = FSMonitorTestScenario(
		name: "high stress",
		fileCount: 100,
		creationDelay: 3_000_000,  // 3ms delay
		streamLatency: 0.1
	)

	/// Extreme batch scenario - no delays, maximum concurrency pressure
	public static let extremeBatch = FSMonitorTestScenario(
		name: "extreme batch",
		fileCount: 100,
		creationDelay: 0,  // No delay
		streamLatency: 0.05
	)

	/// Coalescing scenario - higher latency to allow event batching
	public static let coalescing = FSMonitorTestScenario(
		name: "coalescing",
		fileCount: 100,
		creationDelay: 5_000_000,  // 5ms delay
		streamLatency: 0.2  // Higher latency for batching
	)

	/// Small load scenario - for quick tests
	public static let smallLoad = FSMonitorTestScenario(
		name: "small load",
		fileCount: 25,
		creationDelay: 5_000_000,  // 5ms delay
		streamLatency: 0.05
	)

	/// All standard scenarios for parameterized tests
	public static let allStandard: [FSMonitorTestScenario] = [
		moderateLoad, highStress, extremeBatch, coalescing,
	]

	/// Educational scenarios for unsafe implementations
	public static let educationalUnsafe: [FSMonitorTestScenario] = [
		FSMonitorTestScenario(
			name: "moderate educational",
			fileCount: 25,
			creationDelay: 5_000_000,
			streamLatency: 0.1
		),
		FSMonitorTestScenario(
			name: "high stress educational",
			fileCount: 100,
			creationDelay: 1_000_000,
			streamLatency: 0.05
		),
		FSMonitorTestScenario(
			name: "extreme educational",
			fileCount: 200,
			creationDelay: 0,
			streamLatency: 0.01,
			waitTime: 2_000_000_000  // 2s wait for unsafe scenarios
		),
	]
}

// MARK: - Shared File Creation Utilities

/// Configuration for creating test files
public struct FileCreationConfig: Sendable {
	public let prefix: String
	public let count: Int
	public let delay: UInt64  // nanoseconds between file creation
	public let atomicWrite: Bool
	public let contentTemplate: String  // Use %d for file index
	public let indexFormat: String  // String format for file index (e.g., "%03d", "%05d")

	public init(
		prefix: String,
		count: Int,
		delay: UInt64,
		atomicWrite: Bool = false,
		contentTemplate: String = "Test content %d",
		indexFormat: String = "%05d"
	) {
		self.prefix = prefix
		self.count = count
		self.delay = delay
		self.atomicWrite = atomicWrite
		self.contentTemplate = contentTemplate
		self.indexFormat = indexFormat
	}

	/// Create config from FSMonitorTestScenario
	public static func from(
		scenario: FSMonitorTestScenario,
		prefix: String,
		atomicWrite: Bool = false,
		contentTemplate: String = "Test content %d"
	) -> FileCreationConfig {
		return FileCreationConfig(
			prefix: prefix,
			count: scenario.fileCount,
			delay: scenario.creationDelay,
			atomicWrite: atomicWrite,
			contentTemplate: contentTemplate
		)
	}
}

/// Create test files in a directory with consistent naming and timing
public func createTestFiles(in directory: URL, config: FileCreationConfig) async throws {
	for i in 0..<config.count {
		let filename = "\(config.prefix)_\(String(format: config.indexFormat, i)).txt"
		let fileURL = directory.appendingPathComponent(filename)
		let content = String(format: config.contentTemplate, i)
		try content.write(to: fileURL, atomically: config.atomicWrite, encoding: .utf8)

		if config.delay > 0 {
			try await Task.sleep(nanoseconds: config.delay)
		}
	}
}

/// Create a temporary directory for testing
public func createTempDirectory(prefix: String = "AsyncFileMonitorTest") throws -> URL {
	let tempDir = FileManager.default.temporaryDirectory
		.appendingPathComponent("\(prefix)_\(UUID().uuidString)")
	try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
	return tempDir
}

/// Clean up temporary directory
public func cleanupTempDirectory(_ directory: URL) {
	try? FileManager.default.removeItem(at: directory)
}
