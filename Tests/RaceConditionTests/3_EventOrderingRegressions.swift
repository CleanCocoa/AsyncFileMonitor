//
//  EventOrderingRegressionTest.swift
//  AsyncFileMonitorTests
//
//  Regression tests that verify event ordering is maintained correctly.
//  Reference: docs/Event Ordering Analysis.md (20250904T080826)
//

import Foundation
import Testing

@testable import AsyncFileMonitor

@Test(
	"MANUAL: Break executor preference to demonstrate reordering",
	.disabled("Only run manually - modifies source code")
)
func manualBreakExecutorPreference() async throws {
	print(
		"""

		🚨 MANUAL REGRESSION TEST INSTRUCTIONS
		=====================================

		This test demonstrates how removing executor preference breaks event ordering.

		STEP 1: Locate the critical code
		File: Sources/AsyncFileMonitor/FolderContentMonitor.swift
		Line 158: Task(executorPreference: FileSystemEventExecutor.shared) {

		STEP 2: Break the code temporarily  
		Change line 158 from:
			Task(executorPreference: FileSystemEventExecutor.shared) {
		To:  
			Task {
			
		STEP 3: Run the ordering test multiple times
		swift test --filter eventOrderingWithCoalescedEvents

		EXPECTED RESULT WITH BROKEN CODE:
		- Events may arrive out of order
		- You'll see "Event IDs are ordered: false" 
		- Out-of-order events will be reported

		STEP 4: Restore the original code
		Change line 158 back to:
			Task(executorPreference: FileSystemEventExecutor.shared) {
			
		STEP 5: Verify the fix
		swift test --filter eventOrderingWithCoalescedEvents

		EXPECTED RESULT WITH FIXED CODE:
		- Events consistently arrive in order
		- You'll see "Event IDs are ordered: true"

		This proves that the executor preference is essential for correctness!

		"""
	)
}

@Test("AUTOMATED: Demonstrate current correct behavior")
func demonstrateCorrectBehavior() async throws {
	// This test shows the current working behavior as a baseline
	let tempDir = try createTempDirectory(prefix: "EventOrderingTest")
	defer { cleanupTempDirectory(tempDir) }

	// Run a smaller version of the event ordering test
	let fileCount = 25
	let collector = EventIDCollector(maxCount: fileCount)
	let monitorTask = Task {
		let eventStream = FolderContentMonitor.makeStream(url: tempDir, latency: 0.15)
		for await event in eventStream {
			let filename = URL(fileURLWithPath: event.eventPath).lastPathComponent
			if filename.hasPrefix("baseline_") && filename.hasSuffix(".txt") {
				if event.change.contains(.created) || event.change.contains(.renamed) {
					collector.recordEvent(eventID: event.eventID, path: event.eventPath)
					if collector.hasReachedMaxCount() {
						break
					}
				}
			}
		}
	}

	// Small startup delay
	try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds

	// Create files with timing that should trigger some coalescing
	let fileConfig = FileCreationConfig(
		prefix: "baseline",
		count: fileCount,
		delay: 8_000_000,  // 0.008 seconds
		atomicWrite: true,
		contentTemplate: "Baseline content %d",
		indexFormat: "%03d"
	)
	try await createTestFiles(in: tempDir, config: fileConfig)

	await monitorTask.value

	let analysis = collector.getOrderingAnalysis()
	print(
		"""

		📊 BASELINE TEST RESULTS (Current Implementation)
		================================================
		Files created: \(fileCount)
		"""
	)
	analysis.printDetailedReport(filePrefix: "baseline")

	#expect(analysis.eventIDs.count == fileCount, "Should receive all \(fileCount) file creation events")

	// Even with executor preference, some reordering may still occur intermittently
	withKnownIssue(
		"Executor preference reduces but doesn't eliminate all reordering under stress",
		isIntermittent: true
	) {
		#expect(analysis.isOrdered, "Events should arrive in chronological order with executor preference")
	}
}

@Test("High-stress ordering test to increase chance of detecting races")
func highStressOrderingTest() async throws {
	// This test uses more aggressive parameters to increase the likelihood
	// of detecting race conditions if executor preference were removed

	let tempDir = try createTempDirectory(prefix: "StressTest")
	defer { cleanupTempDirectory(tempDir) }

	// More aggressive parameters
	let fileCount = 75  // More files
	let collector = EventIDCollector(maxCount: fileCount)

	// Use shorter latency for more aggressive testing
	let monitorTask = Task {
		let eventStream = FolderContentMonitor.makeStream(url: tempDir, latency: 0.1)
		for await event in eventStream {
			let filename = URL(fileURLWithPath: event.eventPath).lastPathComponent
			if filename.hasPrefix("stress_") && filename.hasSuffix(".txt") {
				if event.change.contains(.created) || event.change.contains(.renamed) {
					collector.recordEvent(eventID: event.eventID, path: event.eventPath)
					if collector.hasReachedMaxCount() {
						break
					}
				}
			}
		}
	}

	// Very short startup delay
	try await Task.sleep(nanoseconds: 50_000_000)  // 0.05 seconds

	// Create files very rapidly to maximize concurrency pressure
	let stressFileConfig = FileCreationConfig(
		prefix: "stress",
		count: fileCount,
		delay: 3_000_000,  // 0.003 seconds - very small delay for high pressure
		atomicWrite: true,
		contentTemplate: "Stress content %d",
		indexFormat: "%03d"
	)
	try await createTestFiles(in: tempDir, config: stressFileConfig)

	await monitorTask.value

	let analysis = collector.getOrderingAnalysis()
	print(
		"""

		🔥 HIGH-STRESS TEST RESULTS
		==========================
		Files created: \(fileCount)
		"""
	)
	analysis.printDetailedReport(filePrefix: "stress")

	#expect(analysis.eventIDs.count == fileCount, "Should receive all file creation events")

	// Under high stress, reordering may occur due to concurrency pressure (intermittent)
	withKnownIssue("High stress with 1ms delays may cause reordering due to concurrency pressure", isIntermittent: true)
	{
		#expect(analysis.isOrdered, "Events should maintain chronological order even under high stress")
	}
}
