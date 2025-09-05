//
// ActorExecutorCoordination.swift
// RaceConditionTests
//
// Swift Testing implementation examining actor and executor coordination
// in file system monitoring. These tests demonstrate that even with custom
// executors and Task executor preferences, Swift concurrency can still
// cause event reordering under stress conditions.
//
// Reference: 20250904T100923
//

import Foundation
import Testing

@testable import AsyncFileMonitor

// MARK: - Actor/Executor Coordination Baseline Tests

@Test("Actor/Executor coordination maintains order under moderate load")
func actorExecutorModerateLoad() async throws {
	let events = try await runCoordinationTest(
		filePrefix: "moderate",
		fileCount: 25,
		creationDelay: 8_000_000  // 8ms - allows proper ordering
	)

	#expect(events.count > 0, "Should receive file creation events")

	let isChronological = areEventsChronological(events)
	#expect(
		isChronological,
		"Actor/Executor coordination should maintain perfect order under moderate load. Got \(events.count) events with ordering score: \(Int(calculateOrderingScore(received: events.map { $0.filename }, expected: events.map { $0.filename }.sorted()) * 100))%"
	)
}

@Test("Actor/Executor coordination exhibits ordering challenges under high stress")
func actorExecutorHighStress() async throws {
	await withKnownIssue(
		"Actor/Executor coordination cannot eliminate Swift concurrency ordering challenges under high stress",
		isIntermittent: true
	) {
		let events = try await runCoordinationTest(
			filePrefix: "stress",
			fileCount: 100,
			creationDelay: 1_000_000  // 1ms - minimal delay to maximize stress
		)

		#expect(events.count > 0, "Should receive file creation events")

		let isChronological = areEventsChronological(events)
		#expect(
			isChronological,
			"Actor/Executor coordination should maintain order (but may fail due to Swift concurrency scheduling under extreme stress)"
		)
	}
}

// MARK: - Helper Functions

/// Run a coordination test using the copied actor/executor implementation
/// - Parameters:
///   - filePrefix: Prefix for created test files
///   - fileCount: Number of files to create
///   - creationDelay: Delay between file creations in nanoseconds
/// - Returns: Array of received events matching the file prefix
private func runCoordinationTest(
	filePrefix: String,
	fileCount: Int,
	creationDelay: UInt64
) async throws -> [FolderContentChangeEvent] {
	let tempDir = try createTempDirectory(prefix: "\(filePrefix)Test")
	defer { cleanupTempDirectory(tempDir) }

	let monitor = TestActorBasedFileMonitor(url: tempDir)
	var receivedEvents: [FolderContentChangeEvent] = []

	let task = Task {
		let stream = await monitor.makeStream()
		for await event in stream {
			let filename = event.filename
			if filename.hasPrefix(filePrefix) && filename.hasSuffix(".txt") && event.change.contains(.created) {
				receivedEvents.append(event)
			}
		}
	}

	// Small delay for monitor to start
	try await Task.sleep(nanoseconds: 100_000_000)  // 0.1s

	// Create test files
	let fileConfig = FileCreationConfig(
		prefix: filePrefix,
		count: fileCount,
		delay: creationDelay,
		atomicWrite: false
	)
	try await createTestFiles(in: tempDir, config: fileConfig)

	// Wait for events
	try await Task.sleep(nanoseconds: 2_000_000_000)  // 2s

	task.cancel()

	return receivedEvents
}

/// Check if event filenames are in chronological order
private func areEventsChronological(_ events: [FolderContentChangeEvent]) -> Bool {
	let filenames = events.map { $0.filename }
	return areFilenamesChronological(filenames)
}
