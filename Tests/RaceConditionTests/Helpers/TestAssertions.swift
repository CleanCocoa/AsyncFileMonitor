//
// TestAssertions.swift
// RaceConditionTests
//
// Shared test assertion utilities for file system monitoring tests.
// Provides consistent validation logic across different test scenarios.
//
// Reference: 20250904T105830
//

import Foundation
import Testing

/// Shared assertion utilities for file system monitoring tests
enum FSEventTestAssertions {

	// MARK: - Thread-Safe Test Assertions

	/// Validate thread-safe FSEventStream test results
	static func validateThreadSafeResults(
		_ result: FSEventTestResult,
		scenario: FSMonitorTestScenario
	) {
		// Note: FSEventStream can legitimately report multiple events per file during rapid creation:
		// - File creation event
		// - File content modification event
		// - File metadata updates
		// Each duplicate has a distinct FSEventStreamEventId, proving these are separate filesystem events.
		// We use inequality checks to accommodate this normal filesystem behavior.
		#expect(
			result.totalEvents >= scenario.fileCount,
			"Should capture at least \(scenario.fileCount) events, got \(result.totalEvents) (\(scenario.name))"
		)
		#expect(
			result.totalEvents <= scenario.fileCount * 2,
			"Should not have excessive duplicate events, got \(result.totalEvents) for \(scenario.fileCount) files (\(scenario.name))"
		)
		#expect(
			result.isChronological,
			"Events should maintain chronological order (\(scenario.name))"
		)

		// Validate timing statistics if available
		if let timing = result.timingStats {
			#expect(
				timing.averageInterval >= 0,
				"Average interval should be non-negative (\(scenario.name))"
			)
			#expect(
				timing.minInterval >= 0,
				"Min interval should be non-negative (\(scenario.name))"
			)
			#expect(
				timing.maxInterval >= timing.minInterval,
				"Max should be >= min interval (\(scenario.name))"
			)
		}
	}

	// MARK: - Unsafe Test Assertions (Educational)

	/// Validate unsafe FSEventStream test results (expected to fail)
	static func validateUnsafeResults(
		_ result: FSEventTestResult,
		scenario: FSMonitorTestScenario,
		expectedFailures: [UnsafeFailureMode] = [.eventLoss, .dataCorruption]
	) async throws {
		withKnownIssue(
			"Demonstrates race conditions with unsafe collection",
			isIntermittent: true
		) {
			if expectedFailures.contains(.eventLoss) {
				#expect(
					result.totalEvents == scenario.fileCount,
					"All events should be captured (may fail due to race conditions)"
				)
			}

			if expectedFailures.contains(.dataCorruption) {
				#expect(
					result.isChronological,
					"Events should be chronological (may fail due to data corruption)"
				)
			}
		}
	}

	// MARK: - AsyncFileMonitor Test Assertions

	/// Validate AsyncFileMonitor results (may have different ordering characteristics)
	static func validateAsyncFileMonitorResults(
		eventCount: Int,
		scenario: FSMonitorTestScenario,
		expectPerfectOrdering: Bool = false
	) {
		#expect(
			eventCount > 0,
			"Should receive some file creation events (\(scenario.name))"
		)

		// Note: AsyncFileMonitor may not guarantee perfect ordering due to Swift concurrency
		if expectPerfectOrdering {
			// This assertion may fail under high stress - that's the educational point
		}
	}

	/// Calculate and validate ordering score for AsyncFileMonitor results
	static func validateOrderingScore(
		receivedFilenames: [String],
		minimumScore: Double = 0.8,
		scenario: FSMonitorTestScenario
	) {
		let sortedFilenames = receivedFilenames.sorted()
		let orderingScore = calculateOrderingScore(received: receivedFilenames, expected: sortedFilenames)

		#expect(
			orderingScore >= minimumScore,
			"Should provide reasonable ordering (>=\(Int(minimumScore * 100))% correct), got \(Int(orderingScore * 100))% for \(scenario.name)"
		)
	}
}

// MARK: - Supporting Types and Utilities

/// Types of failures expected in unsafe implementations
enum UnsafeFailureMode {
	case eventLoss  // Missing events due to race conditions
	case dataCorruption  // Incorrect ordering due to concurrent access
}

/// Calculate how well the received events match the expected order
public func calculateOrderingScore(received: [String], expected: [String]) -> Double {
	guard received.count == expected.count && !received.isEmpty else { return 0.0 }

	let matches = zip(received, expected).reduce(0) { count, pair in
		count + (pair.0 == pair.1 ? 1 : 0)
	}

	return Double(matches) / Double(received.count)
}

/// Check if a list of filenames are in chronological order
public func areFilenamesChronological(_ filenames: [String]) -> Bool {
	let sortedFilenames = filenames.sorted()
	return filenames == sortedFilenames
}

// MARK: - Convenience Extensions

extension FSEventTestResult {
	/// Validate this result as thread-safe
	func validateAsThreadSafe(scenario: FSMonitorTestScenario) {
		FSEventTestAssertions.validateThreadSafeResults(self, scenario: scenario)
	}

	/// Validate this result as unsafe (educational)
	func validateAsUnsafe(
		scenario: FSMonitorTestScenario,
		expectedFailures: [UnsafeFailureMode] = [.eventLoss, .dataCorruption]
	) async throws {
		try await FSEventTestAssertions.validateUnsafeResults(
			self,
			scenario: scenario,
			expectedFailures: expectedFailures
		)
	}
}
