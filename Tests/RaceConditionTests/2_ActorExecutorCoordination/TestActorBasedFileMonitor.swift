//
// TestActorBasedFileMonitor.swift
// RaceConditionTests
//
// Reference: 20250904T080826
//
// Actor/executor test implementation preserved from the original main approach.
// Demonstrates that even with sophisticated executor-based coordination,
// Swift concurrency can still cause event reordering under stress conditions.
//
// This proved that ordering challenges are due to Swift concurrency fundamentals,
// leading to the development of the direct AsyncStream approach (20250905T073442).
//

import CoreFoundation
import Foundation

@testable import AsyncFileMonitor

/// Test-specific file monitor that uses direct copies of the actual library code
/// to demonstrate that the current executor-based approach faces the same
/// Swift concurrency ordering limitations under stress
struct TestActorBasedFileMonitor {
	let url: URL

	init(url: URL) {
		self.url = url
	}

	/// Create a stream using the actual copied executor and monitor implementation
	func makeStream() async -> AsyncStream<FolderContentChangeEvent> {
		// Use the copied TestFolderContentMonitor - this is identical behavior
		// to the original but uses our copied types for stable baseline
		let monitor = TestFolderContentMonitor(url: url)
		return await monitor.makeStream()
	}
}
