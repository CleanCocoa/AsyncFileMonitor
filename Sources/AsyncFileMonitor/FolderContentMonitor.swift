//
//  FolderContentMonitor.swift
//  AsyncFileMonitor
//
//  Created by Christian Tietze on 08/11/16.
//  Copyright © 2016 Christian Tietze, RxSwiftCommunity (original RxFileMonitor)
//  Copyright © 2025 Christian Tietze (AsyncFileMonitor modernization)
//
//  Reference: 20250905T073442
//
//  Migrated to direct MulticastAsyncStream approach for superior event ordering.
//  Eliminates actor isolation and Swift concurrency Task scheduling that can cause reordering.
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
/// let stream = monitor.makeStream()
///
/// for await event in stream {
///     print("Change detected: \(event.eventPath)")
/// }
/// ```
///
/// ## Architecture
///
/// Uses direct MulticastAsyncStream approach for superior event ordering:
/// - FSEventStream callback → MulticastAsyncStream.send() → AsyncStream continuations
/// - No actor isolation or Task scheduling to prevent event reordering
/// - Swift 6 Mutex for thread-safe subscriber management
/// - OrderedDictionary preserves subscriber registration order
public final class FolderContentMonitor: @unchecked Sendable {
	private let multicastStream = MulticastAsyncStream<FolderContentChangeEvent>()
	private var fileSystemEventStream: FileSystemEventStream?
	private var lifecycleTask: Task<Void, Never>?

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

	/// Create a new monitor for the specified paths.
	///
	/// - Parameters:
	///   - paths: Array of file system paths to monitor
	///   - sinceWhen: FSEvent ID to start monitoring from (default: `kFSEventStreamEventIdSinceNow`)
	///   - latency: Event coalescing interval in seconds (default: `0`)
	public init(
		paths: [String],
		sinceWhen: FSEventStreamEventId = FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
		latency: CFTimeInterval = 0
	) {
		self.paths = paths
		self.latency = latency
		self.sinceWhen = sinceWhen
	}

	/// Create a new monitor for a single URL.
	///
	/// - Parameters:
	///   - url: The file or directory URL to monitor (must be a file URL)
	///   - sinceWhen: FSEvent ID to start monitoring from (default: `kFSEventStreamEventIdSinceNow`)
	///   - latency: Event coalescing interval in seconds (default: `0`)
	public convenience init(
		url: URL,
		sinceWhen: FSEventStreamEventId = FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
		latency: CFTimeInterval = 0
	) {
		precondition(url.isFileURL)
		self.init(
			paths: [url.path],
			sinceWhen: sinceWhen,
			latency: latency
		)
	}

	deinit {
		lifecycleTask?.cancel()
	}

	/// Create a new `AsyncStream` of change events for this monitor.
	///
	/// Multiple streams can be created from the same monitor instance. The monitor
	/// automatically starts when the first stream is created and stops when the last stream ends.
	///
	/// - Returns: An `AsyncStream` of ``FolderContentChangeEvent`` objects
	public func makeStream() -> AsyncStream<FolderContentChangeEvent> {
		setupLifecycleManagement()
		return multicastStream.makeStream()
	}

	/// Set up automatic start/stop lifecycle management based on stream count.
	///
	/// This method ensures that the FSEventStream is started when the first stream is added
	/// and stopped when the last stream is removed.
	private func setupLifecycleManagement() {
		guard lifecycleTask == nil else { return }

		// Set up the lifecycle stream to monitor subscriber changes
		let lifecycleEvents = multicastStream.makeLifecycleStream()

		lifecycleTask = Task {
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
		precondition(
			fileSystemEventStream == nil,
			"Should be impossible to run start twice in a row unless we have a race condition"
		)

		do {
			// Create FileSystemEventStream with direct MulticastAsyncStream approach
			// Events flow directly: FSEventStream callback → MulticastAsyncStream.send() → AsyncStream continuations
			// This eliminates all Swift concurrency Task scheduling that can cause reordering
			let stream = try FileSystemEventStream(
				paths: paths,
				sinceWhen: sinceWhen,
				latency: latency,
				multicastStream: multicastStream
			)

			fileSystemEventStream = stream
		} catch {
			// If FSEventStream creation fails, we can't monitor
			// The fileSystemEventStream remains nil, so no events will be delivered
			print("Failed to create FileSystemEventStream: \(error)")
		}
	}

	private func stop() {
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
	/// - Returns: An `AsyncStream` of ``FolderContentChangeEvent`` objects
	public static func makeStream(
		url: URL,
		sinceWhen: FSEventStreamEventId = FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
		latency: CFTimeInterval = 0
	) -> AsyncStream<FolderContentChangeEvent> {
		let monitor = FolderContentMonitor(
			url: url,
			sinceWhen: sinceWhen,
			latency: latency
		)

		return AsyncStream { continuation in
			Task {
				let stream = monitor.makeStream()
				for await event in stream {
					continuation.yield(event)
				}
				continuation.finish()
				// Keep monitor alive by capturing it
				_ = monitor
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
	/// - Returns: An `AsyncStream` of ``FolderContentChangeEvent`` objects
	public static func makeStream(
		paths: [String],
		sinceWhen: FSEventStreamEventId = FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
		latency: CFTimeInterval = 0
	) -> AsyncStream<FolderContentChangeEvent> {
		let monitor = FolderContentMonitor(
			paths: paths,
			sinceWhen: sinceWhen,
			latency: latency
		)

		// Keep monitor alive as long as stream is active
		return AsyncStream { continuation in
			Task {
				let stream = monitor.makeStream()
				for await event in stream {
					continuation.yield(event)
				}
				continuation.finish()
				// Keep monitor alive by capturing it
				_ = monitor
			}
		}
	}

}
