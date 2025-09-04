//
// FSEventStreamTestRunner.swift
// RaceConditionTests
//
// Concrete FSEventStream test runners that avoid generic class issues.
// This replaces the generic FSEventStreamTestHarness to work around Swift 6 compiler crashes.
//
// Reference: 20250904T105820
//

import Foundation

@testable import AsyncFileMonitor

// MARK: - Global Callback Functions

/// Callback function for thread-safe FSEventStream tests
let threadSafeCallback: FSEventStreamCallback = { (stream, contextInfo, numEvents, eventPaths, eventFlags, eventIDs) in
	guard let contextInfo else { return }
	let collector = Unmanaged<ThreadSafeEventCollector>.fromOpaque(contextInfo).takeUnretainedValue()
	guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }

	for index in 0..<numEvents {
		let filename = URL(fileURLWithPath: paths[index]).lastPathComponent
		if filename.hasSuffix(".txt") {
			collector.recordEvent(eventID: eventIDs[index], path: paths[index])
		}
	}
}

/// Callback function for unsafe FSEventStream tests
let unsafeCallback: FSEventStreamCallback = { (stream, contextInfo, numEvents, eventPaths, eventFlags, eventIDs) in
	guard let contextInfo else { return }
	let collector = Unmanaged<UnsafeEventCollector>.fromOpaque(contextInfo).takeUnretainedValue()
	guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }

	for index in 0..<numEvents {
		let filename = URL(fileURLWithPath: paths[index]).lastPathComponent
		if filename.hasSuffix(".txt") {
			collector.recordEvent(eventID: eventIDs[index], path: paths[index])
		}
	}
}

// MARK: - Configuration

/// Configuration for FSEventStream test execution
struct FSEventStreamTestConfig: Sendable {
	let scenario: FSMonitorTestScenario
	let filePrefix: String
	let concurrentQueue: Bool  // Use concurrent vs serial dispatch queue

	init(
		scenario: FSMonitorTestScenario,
		filePrefix: String = "test",
		concurrentQueue: Bool = false
	) {
		self.scenario = scenario
		self.filePrefix = filePrefix
		self.concurrentQueue = concurrentQueue
	}
}

/// Errors that can occur during FSEventStream testing
enum FSEventStreamTestError: Error {
	case streamCreationFailed
	case streamStartFailed
}

// MARK: - Thread-Safe Test Runner

/// Run a thread-safe FSEventStream test
func runThreadSafeFSEventStreamTest(
	config: FSEventStreamTestConfig,
	collector: ThreadSafeEventCollector
) async throws -> FSEventTestResult {
	let tempDir = try createTempDirectory(prefix: "\(config.filePrefix)Test")
	defer { cleanupTempDirectory(tempDir) }

	// Set up FSEventStream
	var context = FSEventStreamContext(
		version: 0,
		info: Unmanaged.passUnretained(collector).toOpaque(),
		retain: nil,
		release: nil,
		copyDescription: nil
	)

	let callback: FSEventStreamCallback = threadSafeCallback

	let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)

	guard
		let stream = FSEventStreamCreate(
			kCFAllocatorDefault,
			callback,
			&context,
			[tempDir.path] as CFArray,
			FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
			config.scenario.streamLatency,
			flags
		)
	else {
		throw FSEventStreamTestError.streamCreationFailed
	}

	// Configure dispatch queue based on test requirements
	let queueLabel = "\(config.filePrefix)Test"
	let queue =
		config.concurrentQueue
		? DispatchQueue(label: queueLabel, qos: .userInteractive, attributes: .concurrent)
		: DispatchQueue(label: queueLabel, qos: .userInteractive)

	FSEventStreamSetDispatchQueue(stream, queue)

	guard FSEventStreamStart(stream) else {
		FSEventStreamRelease(stream)
		throw FSEventStreamTestError.streamStartFailed
	}

	// Small delay to let stream start
	try await Task.sleep(nanoseconds: 100_000_000)  // 0.1s

	// Create test files
	let fileConfig = FileCreationConfig.from(scenario: config.scenario, prefix: config.filePrefix)
	try await createTestFiles(in: tempDir, config: fileConfig)

	// Wait for events
	try await Task.sleep(nanoseconds: config.scenario.waitTime)

	// Clean up
	FSEventStreamStop(stream)
	FSEventStreamInvalidate(stream)
	FSEventStreamRelease(stream)

	return collector.analyzeEvents()
}

// MARK: - Unsafe Test Runner

/// Run an unsafe FSEventStream test (for educational purposes)
func runUnsafeFSEventStreamTest(
	config: FSEventStreamTestConfig,
	collector: UnsafeEventCollector
) async throws -> FSEventTestResult {
	let tempDir = try createTempDirectory(prefix: "\(config.filePrefix)Test")
	defer { cleanupTempDirectory(tempDir) }

	// Set up FSEventStream
	var context = FSEventStreamContext(
		version: 0,
		info: Unmanaged.passUnretained(collector).toOpaque(),
		retain: nil,
		release: nil,
		copyDescription: nil
	)

	let callback: FSEventStreamCallback = unsafeCallback

	let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)

	guard
		let stream = FSEventStreamCreate(
			kCFAllocatorDefault,
			callback,
			&context,
			[tempDir.path] as CFArray,
			FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
			config.scenario.streamLatency,
			flags
		)
	else {
		throw FSEventStreamTestError.streamCreationFailed
	}

	// Configure dispatch queue based on test requirements
	let queueLabel = "\(config.filePrefix)Test"
	let queue =
		config.concurrentQueue
		? DispatchQueue(label: queueLabel, qos: .userInteractive, attributes: .concurrent)
		: DispatchQueue(label: queueLabel, qos: .userInteractive)

	FSEventStreamSetDispatchQueue(stream, queue)

	guard FSEventStreamStart(stream) else {
		FSEventStreamRelease(stream)
		throw FSEventStreamTestError.streamStartFailed
	}

	// Small delay to let stream start
	try await Task.sleep(nanoseconds: 100_000_000)  // 0.1s

	// Create test files
	let fileConfig = FileCreationConfig.from(scenario: config.scenario, prefix: config.filePrefix)
	try await createTestFiles(in: tempDir, config: fileConfig)

	// Wait for events
	try await Task.sleep(nanoseconds: config.scenario.waitTime)

	// Clean up
	FSEventStreamStop(stream)
	FSEventStreamInvalidate(stream)
	FSEventStreamRelease(stream)

	return collector.analyzeEvents()
}

// MARK: - Factory Functions

/// Create a thread-safe test configuration and run the test
func createThreadSafeHarness(
	scenario: FSMonitorTestScenario,
	filePrefix: String = "threadsafe"
) -> ThreadSafeHarness {
	let config = FSEventStreamTestConfig(
		scenario: scenario,
		filePrefix: filePrefix,
		concurrentQueue: false  // Serial queue for thread-safe baseline
	)
	let collector = ThreadSafeEventCollector()
	return ThreadSafeHarness(config: config, collector: collector)
}

/// Create an unsafe test configuration and run the test (for educational purposes)
func createUnsafeHarness(
	scenario: FSMonitorTestScenario,
	filePrefix: String = "unsafe"
) -> UnsafeHarness {
	let config = FSEventStreamTestConfig(
		scenario: scenario,
		filePrefix: filePrefix,
		concurrentQueue: true  // Concurrent queue to maximize race conditions
	)
	let collector = UnsafeEventCollector()
	return UnsafeHarness(config: config, collector: collector)
}

// MARK: - Concrete Harness Types

struct ThreadSafeHarness {
	private let config: FSEventStreamTestConfig
	private let collector: ThreadSafeEventCollector

	init(config: FSEventStreamTestConfig, collector: ThreadSafeEventCollector) {
		self.config = config
		self.collector = collector
	}

	func runTest() async throws -> FSEventTestResult {
		return try await runThreadSafeFSEventStreamTest(config: config, collector: collector)
	}
}

struct UnsafeHarness {
	private let config: FSEventStreamTestConfig
	private let collector: UnsafeEventCollector

	init(config: FSEventStreamTestConfig, collector: UnsafeEventCollector) {
		self.config = config
		self.collector = collector
	}

	func runTest() async throws -> FSEventTestResult {
		return try await runUnsafeFSEventStreamTest(config: config, collector: collector)
	}
}
