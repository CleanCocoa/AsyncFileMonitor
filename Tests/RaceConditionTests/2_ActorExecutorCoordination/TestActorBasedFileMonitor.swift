//
// TestActorBasedFileMonitor.swift
// RaceConditionTests
//
// Test implementation using the actual copied FileSystemEventExecutor and
// FileSystemEventStream code to demonstrate that even with the library's
// sophisticated executor-based approach, Swift concurrency can still cause
// event reordering under stress conditions.
//
// This proves that the current implementation already uses best practices
// and the ordering challenges are due to Swift concurrency fundamentals.
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
