//
// UnsafeRaceConditionTests.swift
// RaceConditionTests
//
// Swift Testing implementation of unsafe FSEventStream tests that deliberately
// demonstrate race conditions and data corruption for educational purposes.
// These tests use withKnownIssue to handle expected failures gracefully.
//
// Reference: 20250904T100917
//

import Foundation
import Testing

// MARK: - Unsafe Race Condition Tests

/// Test that demonstrates race conditions when thread safety is missing - moderate load
@Test("FSEventStream without thread safety demonstrates race conditions - moderate load")
func fsEventStreamUnsafeModerate() async throws {
	let harness = createUnsafeHarness(scenario: StandardTestScenarios.educationalUnsafe[0])
	let result = try await harness.runTest()
	try await result.validateAsUnsafe(scenario: StandardTestScenarios.educationalUnsafe[0])
}

/// Test that demonstrates race conditions when thread safety is missing - high stress
@Test("FSEventStream without thread safety demonstrates race conditions - high stress")
func fsEventStreamUnsafeHighStress() async throws {
	let harness = createUnsafeHarness(scenario: StandardTestScenarios.educationalUnsafe[1])
	let result = try await harness.runTest()
	try await result.validateAsUnsafe(scenario: StandardTestScenarios.educationalUnsafe[1])
}

/// Test that demonstrates race conditions when thread safety is missing - extreme stress
@Test("FSEventStream without thread safety demonstrates race conditions - extreme stress")
func fsEventStreamUnsafeExtremeStress() async throws {
	let harness = createUnsafeHarness(scenario: StandardTestScenarios.educationalUnsafe[2])
	let result = try await harness.runTest()
	try await result.validateAsUnsafe(scenario: StandardTestScenarios.educationalUnsafe[2])
}

// MARK: - Educational Race Condition Analysis

/// Test that documents common race condition failure modes
@Test("Unsafe FSEventStream documents race condition failure modes")
func unsafeFSEventStreamFailureModes() async throws {
	// This test demonstrates the educational value of the unsafe implementation
	let scenario = FSMonitorTestScenario(
		name: "educational failure modes",
		fileCount: 50,
		creationDelay: 2_000_000,  // 2ms
		streamLatency: 0.05
	)

	let harness = createUnsafeHarness(scenario: scenario)
	let result = try await harness.runTest()

	// Document observed behavior for educational purposes
	if result.totalEvents < 50 {
		_ = 50 - result.totalEvents
		// This is expected - race conditions cause event loss
	}

	if !result.isChronological {
		// This may be due to data corruption from race conditions
	}

	// The key insight: Even partial success demonstrates the problem
	// We don't use #expect here as we're documenting failure modes, not asserting success
}
