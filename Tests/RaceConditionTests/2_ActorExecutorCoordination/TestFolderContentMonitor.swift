//
//  TestFolderContentMonitor.swift
//  RaceConditionTests
//
//  Reference: 20250904T080826
//
//  Actor/executor implementation of FolderContentMonitor preserved for testing.
//  This was the main implementation before migration to direct AsyncStream approach.
//  Isolated copy maintains stable baseline for comparison with current approach.
//

import Foundation

@testable import AsyncFileMonitor

/// Monitor for a particular file or folder.
///
/// `TestFolderContentMonitor` wraps FSEventStream to provide an async Swift API
/// for monitoring file system changes. It maintains perfect event ordering under
/// normal conditions but may experience reordering under extreme stress due to
/// Swift concurrency's cooperative scheduling model.
///
/// ## Basic Usage
///
/// ```swift
/// let monitor = TestFolderContentMonitor(url: myFolderURL)
/// let stream = await monitor.makeStream()
///
/// for await event in stream {
///     print("File changed: \(event)")
/// }
/// ```
public actor TestFolderContentMonitor {
	fileprivate let registrar = TestStreamRegistrar<FolderContentChangeEvent>()
	fileprivate var fileSystemEventStream: TestFileSystemEventStream?

	/// The paths being monitored.
	public let paths: [String]

	/// Event coalescing interval in seconds.
	public let latency: CFTimeInterval

	/// FSEvent ID to start monitoring from.
	public let sinceWhen: FSEventStreamEventId

	// Use the shared TestFileSystemEventExecutor for all file monitoring operations
	nonisolated public var unownedExecutor: UnownedSerialExecutor {
		if #available(macOS 15.0, *) {
			return TestFileSystemEventExecutor.shared.asUnownedSerialExecutor()
		} else {
			fatalError("macOS 15.0 or later is required")
		}
	}

	/// Initialize a folder content monitor for a single path.
	///
	/// - Parameters:
	///   - url: The file system location to monitor
	///   - sinceWhen: FSEvent ID to start monitoring from (default: since now)
	///   - latency: Event coalescing interval in seconds (default: 50ms)
	public init(
		url: URL,
		sinceWhen: FSEventStreamEventId = FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
		latency: CFTimeInterval = 0.05
	) {
		self.paths = [url.path]
		self.sinceWhen = sinceWhen
		self.latency = latency
	}

	/// Initialize a folder content monitor for multiple paths.
	///
	/// - Parameters:
	///   - paths: The file system paths to monitor
	///   - sinceWhen: FSEvent ID to start monitoring from (default: since now)
	///   - latency: Event coalescing interval in seconds (default: 50ms)
	public init(
		paths: [String],
		sinceWhen: FSEventStreamEventId = FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
		latency: CFTimeInterval = 0.05
	) {
		self.paths = paths
		self.sinceWhen = sinceWhen
		self.latency = latency
	}

	/// Create a new stream for monitoring file system events.
	///
	/// Each call creates an independent stream that will receive all file system
	/// events for the monitored paths. The monitor starts when the first stream
	/// is created and stops when all streams are terminated.
	///
	/// - Returns: An `AsyncStream` of `FolderContentChangeEvent` values
	public func makeStream() async -> AsyncStream<FolderContentChangeEvent> {
		// Set up lifecycle management: start monitoring on first stream, stop on last
		let lifecycleStream = await registrar.makeLifecycleStream()
		Task(executorPreference: TestFileSystemEventExecutor.shared) {
			for await event in lifecycleStream {
				switch event {
				case .firstStreamAdded:
					await self.start()
				case .lastStreamRemoved:
					await self.stop()
				}
			}
		}

		// Return the actual content stream
		return await registrar.makeStream()
	}

	/// Broadcast events to all registered streams.
	fileprivate func broadcast(folderContentChangeEvents events: [FolderContentChangeEvent]) async {
		for event in events {
			await registrar.yield(event)
		}
	}

	private func start() {
		TestFileSystemEventExecutor.shared.preconditionIsolated("start() must be called on TestFileSystemEventExecutor")

		precondition(
			fileSystemEventStream == nil,
			"FileSystemEventStream should not be set when start() is called"
		)

		do {
			let stream = try TestFileSystemEventStream(
				paths: paths,
				sinceWhen: sinceWhen,
				latency: latency,
				queue: TestFileSystemEventExecutor.shared.underlyingQueue
			) { [weak self] events in
				guard let self else { return }

				// This executor preference is used to maintain event ordering across Task boundaries.
				// However, it's important to note that this is necessary but not sufficient for perfect ordering
				// under all conditions, particularly when the system is under high stress or experiencing timing
				// variations. This executor preference is necessary but not sufficient for perfect ordering.
				// See: docs/FSEventStream Ordering Findings.md and docs/Event Reordering with Executor.md
				Task(executorPreference: TestFileSystemEventExecutor.shared) {
					await self.broadcast(folderContentChangeEvents: events)
				}
			}
			self.fileSystemEventStream = stream
		} catch {
			// If FSEventStream creation fails, we can't monitor
			// The fileSystemEventStream remains nil, so no events will be delivered
			print("Failed to create TestFileSystemEventStream: \(error)")
		}
	}

	private func stop() {
		dispatchPrecondition(condition: .onQueue(TestFileSystemEventExecutor.shared.underlyingQueue))

		// Simply release the file system event stream - its deinit will handle cleanup
		fileSystemEventStream = nil
	}
}

// MARK: - Convenience Methods

extension TestFolderContentMonitor {
	/// Create an `AsyncStream` to monitor file system events.
	///
	/// This creates a new ``TestFolderContentMonitor`` instance and returns its first stream.
	/// The monitor will be kept alive as long as the stream is active.
	///
	/// - Parameters:
	///   - url: The file system location to monitor
	///   - sinceWhen: FSEvent ID to start monitoring from
	///   - latency: Event coalescing interval in seconds
	///   - qos: Quality of service for the monitoring queue
	/// - Returns: An `AsyncStream` of `FolderContentChangeEvent` values
	@available(macOS 15.0, *)
	public static func monitor(
		url: URL,
		sinceWhen: FSEventStreamEventId = FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
		latency: CFTimeInterval = 0.05,
		qos: DispatchQoS = .userInteractive
	) -> AsyncStream<FolderContentChangeEvent> {
		let monitor = TestFolderContentMonitor(
			url: url,
			sinceWhen: sinceWhen,
			latency: latency
		)

		return AsyncStream { continuation in
			Task(executorPreference: TestFileSystemEventExecutor.shared) {
				let stream = await monitor.makeStream()
				for await event in stream {
					continuation.yield(event)
				}
				continuation.finish()
			}
		}
	}

	/// Create an `AsyncStream` to monitor file system events.
	///
	/// This creates a new ``TestFolderContentMonitor`` instance and returns its first stream.
	/// The monitor will be kept alive as long as the stream is active.
	///
	/// - Parameters:
	///   - paths: The file system paths to monitor
	///   - sinceWhen: FSEvent ID to start monitoring from
	///   - latency: Event coalescing interval in seconds
	///   - qos: Quality of service for the monitoring queue
	/// - Returns: An `AsyncStream` of `FolderContentChangeEvent` values
	@available(macOS 15.0, *)
	public static func monitor(
		paths: [String],
		sinceWhen: FSEventStreamEventId = FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
		latency: CFTimeInterval = 0.05,
		qos: DispatchQoS = .userInteractive
	) -> AsyncStream<FolderContentChangeEvent> {
		let monitor = TestFolderContentMonitor(
			paths: paths,
			sinceWhen: sinceWhen,
			latency: latency
		)

		return AsyncStream { continuation in
			Task(executorPreference: TestFileSystemEventExecutor.shared) {
				let stream = await monitor.makeStream()
				for await event in stream {
					continuation.yield(event)
				}
				continuation.finish()
			}
		}
	}

	/// Create a Task with TestFileSystemEventExecutor preference.
	///
	/// This ensures that the task and its structured concurrency children
	/// (async let, TaskGroup) will prefer to run on the shared TestFileSystemEventExecutor,
	/// avoiding unnecessary context switches.
	@available(macOS 15.0, *)
	public static func withExecutorPreference<Success>(
		priority: TaskPriority? = nil,
		operation: @Sendable @escaping () async throws -> Success
	) -> Task<Success, Error> {
		Task(executorPreference: TestFileSystemEventExecutor.shared, priority: priority, operation: operation)
	}

	/// Execute operation with TestFileSystemEventExecutor preference.
	///
	/// This ensures that the operation and its structured concurrency children
	/// will prefer to run on the shared TestFileSystemEventExecutor, avoiding unnecessary
	/// context switches.
	@available(macOS 15.0, *)
	public static func withExecutorPreference<T>(
		operation: @Sendable () async throws -> T
	) async rethrows -> T {
		try await withTaskExecutorPreference(TestFileSystemEventExecutor.shared, operation: operation)
	}
}
