//
// ThreadSafeBaselineTests.swift
// RaceConditionTests
//
// Swift Testing implementation of thread-safe FSEventStream baseline tests.
// These tests demonstrate the correct, thread-safe way to use FSEventStream
// directly with the C API, proving that FSEventStream maintains perfect ordering.
//
// Reference: 20250904T100930
//

import Foundation
import Testing

// MARK: - Thread-Safe FSEventStream Baseline Tests

/// Test FSEventStream C API with proper thread safety under various timing scenarios
@Test(
	"FSEventStream maintains perfect ordering with thread safety",
	arguments: StandardTestScenarios.allStandard.map { ($0.name, $0) }
)
func fsEventStreamThreadSafeParameterized(testName: String, scenario: FSMonitorTestScenario) async throws {
	let harness = createThreadSafeHarness(scenario: scenario)
	let result = try await harness.runTest()
	result.validateAsThreadSafe(scenario: scenario)
}
