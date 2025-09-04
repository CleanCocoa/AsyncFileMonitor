//
//  FolderContentMonitor.swift
//  AsyncFileMonitor
//
//  Created by Christian Tietze on 08/11/16.
//  Copyright © 2016 Christian Tietze, RxSwiftCommunity (original RxFileMonitor)
//  Copyright © 2025 Christian Tietze (AsyncFileMonitor modernization)
//

import Foundation

/// Monitor for a particular file or folder.
///
/// ``Change`` events will fire when the contents of the URL changes. If the monitored path is a
/// folder, it will fire when you add/remove/rename files or folders below the reference ``paths``.
///
/// See ``Change`` for an incomprehensive list of event details that will be reported.
///
/// ## Usage
///
/// Create a monitor instance and call ``makeStream()`` to get an `AsyncStream` of
/// ``FolderContentChangeEvent`` objects:
///
/// ```swift
/// let monitor = FolderContentMonitor(url: myFolderURL)
/// let stream = await monitor.makeStream()
///
/// for await event in stream {
///     print("Change detected: \(event.eventPath)")
/// }
/// ```
public actor FolderContentMonitor {
	fileprivate let registrar = StreamRegistrar<FolderContentChangeEvent>()
	fileprivate var fileSystemEventStream: FileSystemEventStream?

	/// The paths being monitored.
	///
	/// This array contains the file system paths that this monitor is watching for changes.
	public let paths: [String]

	/// The latency setting for event coalescing.
	///
	/// Interval (in seconds) that the system should wait before reporting events,
	/// allowing multiple related events to be coalesced. A value of `0.0` means no delay.
	public let latency: CFTimeInterval

	/// The FSEventStreamEventId to start from.
	///
	/// This determines which events should be reported. Use `kFSEventStreamEventIdSinceNow`
	/// to only receive events that occur after monitoring starts.
	public let sinceWhen: FSEventStreamEventId

	// Use the shared FileSystemEventExecutor for all file monitoring operations
	nonisolated public var unownedExecutor: UnownedSerialExecutor {
		if #available(macOS 15.0, *) {
			return FileSystemEventExecutor.shared.asUnownedSerialExecutor()
		} else {
			fatalError("macOS 15.0 or later is required")
		}
	}

	private var registrarLifecycle: Task<Void, Never>?

	/// Create a new monitor for the specified paths.
	///
	/// - Parameters:
	///   - paths: Array of file system paths to monitor
	///   - sinceWhen: FSEvent ID to start monitoring from (default: `kFSEventStreamEventIdSinceNow`)
	///   - latency: Event coalescing interval in seconds (default: `0`)
	///   - qos: Quality of service for the monitoring queue (default: `.userInteractive`)
	public init(
		paths: [String],
		sinceWhen: FSEventStreamEventId = FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
		latency: CFTimeInterval = 0,
		qos: DispatchQoS = .userInteractive
	) {
		self.paths = paths
		self.latency = latency
		self.sinceWhen = sinceWhen
		self.registrarLifecycle = nil
	}

	/// Create a new monitor for a single URL.
	///
	/// - Parameters:
	///   - url: The file or directory URL to monitor (must be a file URL)
	///   - sinceWhen: FSEvent ID to start monitoring from (default: `kFSEventStreamEventIdSinceNow`)
	///   - latency: Event coalescing interval in seconds (default: `0`)
	///   - qos: Quality of service for the monitoring queue (default: `.userInteractive`)
	public init(
		url: URL,
		sinceWhen: FSEventStreamEventId = FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
		latency: CFTimeInterval = 0,
		qos: DispatchQoS = .userInteractive
	) {
		precondition(url.isFileURL)
		self.init(
			paths: [url.path],
			sinceWhen: sinceWhen,
			latency: latency,
			qos: qos
		)
	}

	deinit {
		registrarLifecycle?.cancel()
	}

	/// Create a new `AsyncStream` of change events for this monitor.
	///
	/// Multiple streams can be created from the same monitor instance. The monitor
	/// automatically starts when the first stream is created and stops when the last stream ends.
	///
	/// - Returns: An `AsyncStream` of ``FolderContentChangeEvent`` objects
	public func makeStream() async -> AsyncStream<FolderContentChangeEvent> {
		await setupLifecycleManagement()
		return await registrar.makeStream()
	}

	/// Set up automatic start/stop lifecycle management based on stream count.
	///
	/// This method ensures that the FSEventStream is started when the first stream is added
	/// and stopped when the last stream is removed.
	private func setupLifecycleManagement() async {
		guard registrarLifecycle == nil else { return }

		// Set up the lifecycle stream first to avoid race condition
		let lifecycleEvents = await registrar.makeLifecycleStream()

		registrarLifecycle = Task {
			for await event in lifecycleEvents {
				switch event {
				case .firstStreamAdded:
					start()
				case .lastStreamRemoved:
					stop()
				}
			}
		}
	}

	private func start() {
		FileSystemEventExecutor.shared.preconditionIsolated("start() must be called on FileSystemEventExecutor")

		precondition(
			fileSystemEventStream == nil,
			"Should be impossible to run start twice in a row unless we have a race condition"
		)

		do {
			let stream = try FileSystemEventStream(
				paths: paths,
				sinceWhen: sinceWhen,
				latency: latency,
				queue: FileSystemEventExecutor.shared.underlyingQueue
			) { [weak self] events in
				guard let self else { return }
				// CRITICAL: Executor preference prevents severe event reordering race conditions. (ref: 20250904T080826)
				// FSEventStream itself delivers events in perfect chronological order, but the Swift
				// concurrency pipeline (Task creation → actor calls → AsyncStream) can introduce timing
				// variations. This executor preference is necessary but not sufficient for perfect ordering.
				// See: docs/FSEventStream Ordering Findings.md and docs/Event Reordering with Executor.md
				Task(executorPreference: FileSystemEventExecutor.shared) {
					await self.broadcast(folderContentChangeEvents: events)
				}
			}

			fileSystemEventStream = stream
		} catch {
			// If FSEventStream creation fails, we can't monitor
			// The fileSystemEventStream remains nil, so no events will be delivered
			print("Failed to create FileSystemEventStream: \(error)")
		}
	}

	private func stop() {
		dispatchPrecondition(condition: .onQueue(FileSystemEventExecutor.shared.underlyingQueue))

		// Simply release the file system event stream - its deinit will handle cleanup
		fileSystemEventStream = nil
	}

	// MARK: - Static Convenience Methods

	/// Create an `AsyncStream` to monitor file system events.
	///
	/// This creates a new ``FolderContentMonitor`` instance and returns its first stream.
	/// The monitor will be kept alive as long as the stream is active.
	///
	/// - Parameters:
	///   - url: The file or directory URL to monitor
	///   - sinceWhen: FSEvent ID to start monitoring from (default: `kFSEventStreamEventIdSinceNow`)
	///   - latency: Event coalescing interval in seconds (default: `0`)
	///   - qos: Quality of service for the monitoring queue (default: `.userInteractive`)
	/// - Returns: An `AsyncStream` of ``FolderContentChangeEvent`` objects
	nonisolated public static func makeStream(
		url: URL,
		sinceWhen: FSEventStreamEventId = FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
		latency: CFTimeInterval = 0,
		qos: DispatchQoS = .userInteractive
	) -> AsyncStream<FolderContentChangeEvent> {
		let monitor = FolderContentMonitor(
			url: url,
			sinceWhen: sinceWhen,
			latency: latency,
			qos: qos
		)

		return AsyncStream { continuation in
			Task(executorPreference: FileSystemEventExecutor.shared) {
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
	/// This creates a new ``FolderContentMonitor`` instance and returns its first stream.
	/// The monitor will be kept alive as long as the stream is active.
	///
	/// - Parameters:
	///   - paths: Array of file or directory paths to monitor
	///   - sinceWhen: FSEvent ID to start monitoring from (default: `kFSEventStreamEventIdSinceNow`)
	///   - latency: Event coalescing interval in seconds (default: `0`)
	///   - qos: Quality of service for the monitoring queue (default: `.userInteractive`)
	/// - Returns: An `AsyncStream` of ``FolderContentChangeEvent`` objects
	nonisolated public static func makeStream(
		paths: [String],
		sinceWhen: FSEventStreamEventId = FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
		latency: CFTimeInterval = 0,
		qos: DispatchQoS = .userInteractive
	) -> AsyncStream<FolderContentChangeEvent> {
		let monitor = FolderContentMonitor(
			paths: paths,
			sinceWhen: sinceWhen,
			latency: latency,
			qos: qos
		)

		// Keep monitor alive as long as stream is active
		return AsyncStream { continuation in
			Task {
				let stream = await monitor.makeStream()
				for await event in stream {
					continuation.yield(event)
				}
				continuation.finish()
				// Monitor will be deallocated when stream ends
				_ = monitor
			}
		}
	}

	nonisolated fileprivate func broadcast(folderContentChangeEvents events: [FolderContentChangeEvent]) async {
		for event in events {
			await registrar.yield(event)
		}
	}

	/// Create a task with the file system event executor preference.
	///
	/// This ensures that the task and its structured concurrency children
	/// (async let, TaskGroup) will prefer to run on the shared FileSystemEventExecutor,
	/// avoiding unnecessary context switches.
	@available(macOS 15.0, *)
	public func createTask<Success>(
		priority: TaskPriority? = nil,
		operation: @Sendable @escaping () async throws -> Success
	) -> Task<Success, Error> {
		Task(executorPreference: FileSystemEventExecutor.shared, priority: priority, operation: operation)
	}

	/// Execute an operation with the file system event executor preference.
	///
	/// This ensures that the operation and its structured concurrency children
	/// will prefer to run on the shared FileSystemEventExecutor, avoiding unnecessary
	/// context switches.
	@available(macOS 15.0, *)
	public func withExecutorPreference<T>(
		operation: @Sendable () async throws -> T
	) async rethrows -> T {
		try await withTaskExecutorPreference(FileSystemEventExecutor.shared, operation: operation)
	}
}
