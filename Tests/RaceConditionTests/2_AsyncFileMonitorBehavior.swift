//
// AsyncFileMonitorOrderingTests.swift
// RaceConditionTests
//
// Swift Testing implementation comparing AsyncFileMonitor behavior against
// the FSEventStream baseline. These tests demonstrate the impact of Swift
// concurrency on event ordering.
//
// Reference: 20250904T100923
//

import Foundation
import Testing

@testable import AsyncFileMonitor

// MARK: - AsyncFileMonitor vs FSEventStream Baseline Comparison

@Test("AsyncFileMonitor maintains order under moderate load")
func asyncFileMonitorModerateLoad() async throws {
	let config = AsyncFileMonitorTestConfig(
		fileCount: 25,
		filePrefix: "async_test",
		creationDelay: 8_000_000  // 8ms delay to match baseline test
	)

	let events = try await runAsyncFileMonitorTest(config: config)

	#expect(events.count > 0, "Should receive some file creation events")

	let isChronological = areEventsChronological(events)

	#expect(
		isChronological,
		"AsyncFileMonitor should maintain perfect chronological order under moderate load. Got \(events.count) events with ordering score: \(Int(calculateOrderingScore(received: events.map { $0.filename }, expected: events.map { $0.filename }.sorted()) * 100))%"
	)
}

@Test("AsyncFileMonitor behavior under high stress usually breaks order")
func asyncFileMonitorHighStress() async throws {
	await withKnownIssue("Swift concurrency may cause event reordering under high load", isIntermittent: true) {
		let config = AsyncFileMonitorTestConfig(
			fileCount: 100,
			filePrefix: "stress_test",
			creationDelay: 1_000_000,  // 1ms - minimal delay to maximize concurrency pressure
			waitTime: 2_000_000_000  // 2s - longer wait for high stress
		)

		let events = try await runAsyncFileMonitorTest(config: config)

		#expect(events.count > 0, "Should receive file creation events")

		// Check if events arrived in creation order
		let isChronological = areEventsChronological(events)

		// This may fail due to Swift concurrency reordering - that's the point of this test
		#expect(isChronological, "Events should arrive in chronological order (may fail due to Swift concurrency)")
	}
}

// MARK: - Helper Functions

/// Configuration for AsyncFileMonitor tests
struct AsyncFileMonitorTestConfig {
	let fileCount: Int
	let filePrefix: String
	let creationDelay: UInt64
	let waitTime: UInt64

	/// Initialize with custom wait time
	init(fileCount: Int, filePrefix: String, creationDelay: UInt64, waitTime: UInt64 = 1_000_000_000) {
		self.fileCount = fileCount
		self.filePrefix = filePrefix
		self.creationDelay = creationDelay
		self.waitTime = waitTime
	}
}

/// Run an AsyncFileMonitor test with specified configuration
/// - Parameter config: Test configuration parameters
/// - Returns: Array of received events matching the file prefix with .created flag
private func runAsyncFileMonitorTest(config: AsyncFileMonitorTestConfig) async throws -> [FolderContentChangeEvent] {
	let tempDir = try createTempDirectory(prefix: "\(config.filePrefix)Test")
	defer { cleanupTempDirectory(tempDir) }

	let monitor = FolderContentMonitor(url: tempDir)
	var receivedEvents: [FolderContentChangeEvent] = []

	let task = Task {
		let stream = await monitor.makeStream()
		for await event in stream {
			let filename = event.filename
			if filename.hasPrefix(config.filePrefix) && filename.hasSuffix(".txt") && event.change.contains(.created) {
				receivedEvents.append(event)
			}
		}
	}

	// Small delay for monitor to start
	try await Task.sleep(nanoseconds: 100_000_000)  // 0.1s

	// Create test files
	let fileConfig = FileCreationConfig(
		prefix: config.filePrefix,
		count: config.fileCount,
		delay: config.creationDelay,
		atomicWrite: false
	)
	try await createTestFiles(in: tempDir, config: fileConfig)

	// Wait for events
	try await Task.sleep(nanoseconds: config.waitTime)

	task.cancel()

	return receivedEvents
}

/// Check if event filenames are in chronological order
private func areEventsChronological(_ events: [FolderContentChangeEvent]) -> Bool {
	let filenames = events.map { $0.filename }
	return areFilenamesChronological(filenames)
}
