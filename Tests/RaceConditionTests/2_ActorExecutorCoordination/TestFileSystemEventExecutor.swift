//
//  TestFileSystemEventExecutor.swift
//  RaceConditionTests
//
//  Reference: 20250904T080826
//
//  Actor/executor implementation of FileSystemEventExecutor preserved for testing.
//  This custom executor was part of the main implementation before migration.
//  Demonstrates that even custom executors can't prevent Swift concurrency reordering.
//

import Foundation

/// A custom executor for file system event monitoring that provides both
/// serial isolation (for actor semantics) and task execution preference.
///
/// This executor conforms to both `SerialExecutor` and `TaskExecutor`,
/// allowing it to:
/// - Provide serial isolation for actors (via SerialExecutor)
/// - Serve as a task executor preference to avoid unnecessary hops (via TaskExecutor)
///
/// The executor is backed by a dispatch queue to ensure serial execution and maintains
/// chronological event ordering. (ref: 20250904T080826)
@available(macOS 15.0, *)
final class TestFileSystemEventExecutor: SerialExecutor, TaskExecutor {
	static let shared = TestFileSystemEventExecutor(
		label: "TestAsyncFileMonitor_FileSystemEventExecutor",
		qos: .userInteractive
	)

	private let queue: DispatchSerialQueue
	private let label: String

	/// Initialize a new file system event executor.
	///
	/// - Parameters:
	///   - label: A label for the underlying dispatch queue
	///   - qos: Quality of service for the dispatch queue
	init(label: String, qos: DispatchQoS = .userInteractive) {
		self.label = label
		self.queue = DispatchSerialQueue(label: label, qos: qos)
	}

	/// Enqueue a job for execution on this executor.
	///
	/// This implementation satisfies both SerialExecutor and TaskExecutor
	/// requirements, maintaining serial execution semantics.
	func enqueue(_ job: consuming ExecutorJob) {
		let unownedJob = UnownedJob(job)
		let unownedSerialExecutor = self.asUnownedSerialExecutor()
		let unownedTaskExecutor = self.asUnownedTaskExecutor()
		queue.async {
			unownedJob.runSynchronously(
				isolatedTo: unownedSerialExecutor,
				taskExecutor: unownedTaskExecutor
			)
		}
	}

	/// Get an unowned reference to this serial executor.
	@inlinable
	func asUnownedSerialExecutor() -> UnownedSerialExecutor {
		UnownedSerialExecutor(ordinary: self)
	}

	/// Get an unowned reference to this task executor.
	@inlinable
	func asUnownedTaskExecutor() -> UnownedTaskExecutor {
		UnownedTaskExecutor(ordinary: self)
	}

	/// Assert that the current execution context is isolated to this executor.
	///
	/// This is useful for debugging and ensuring code is running on the expected executor.
	func assertIsolated() {
		queue.assertIsolated()
	}

	/// Check that the current execution context is isolated to this executor.
	///
	/// - Parameter message: An optional message to include in the precondition failure
	func preconditionIsolated(_ message: String? = nil) {
		if let message {
			queue.preconditionIsolated(message)
		} else {
			queue.preconditionIsolated()
		}
	}

	// Internal queue accessor for compatibility
	internal var underlyingQueue: DispatchSerialQueue {
		queue
	}

	/// Check if the current task is using this executor as its task executor preference.
	///
	/// This is useful for verifying that tasks are running on the expected executor.
	static func isCurrentTaskExecutor(_ executor: TestFileSystemEventExecutor) -> Bool {
		withUnsafeCurrentTask { task in
			guard let task else { return false }
			guard let currentTaskExecutor = task.unownedTaskExecutor else { return false }
			return currentTaskExecutor == executor.asUnownedTaskExecutor()
		}
	}
}
