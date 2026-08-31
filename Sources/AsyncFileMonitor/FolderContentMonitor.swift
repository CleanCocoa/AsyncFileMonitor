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
//  Main monitor implementation using direct MulticastAsyncStream approach for reliable event ordering.
//

import Foundation
import Synchronization

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
nonisolated public final class FolderContentMonitor: Sendable {
	private enum State: ~Copyable {
		case idle
		case awaitingSubscribers(lifecycleTask: Task<Void, Never>)
		case streaming(lifecycleTask: Task<Void, Never>, eventStream: FileSystemEventStream)
	}

	private let multicastStream = MulticastAsyncStream<FolderContentChangeEvent>()
	private let state = Mutex(State.idle)

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
		state.withLock { state in
			switch consume state {
			case .idle:
				state = .idle
			case .awaitingSubscribers(let task):
				task.cancel()
				state = .idle
			case .streaming(let task, _):
				task.cancel()
				state = .idle
			}
		}
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
		state.withLock { state in
			switch consume state {
			case .idle:
				let lifecycleEvents = multicastStream.makeLifecycleStream()
				let task = Task { [weak self] in
					for await event in lifecycleEvents {
						switch event {
						case .firstStreamAdded: self?.start()
						case .lastStreamRemoved: self?.stop()
						}
					}
				}
				state = .awaitingSubscribers(lifecycleTask: task)
			case .awaitingSubscribers(let task):
				state = .awaitingSubscribers(lifecycleTask: task)
			case .streaming(let task, let eventStream):
				state = .streaming(lifecycleTask: task, eventStream: eventStream)
			}
		}
	}

	private func start() {
		state.withLock { state in
			switch consume state {
			case .awaitingSubscribers(let task):
				do {
					let eventStream = try FileSystemEventStream.make(
						paths: paths,
						sinceWhen: sinceWhen,
						latency: latency,
						eventHandler: { [multicastStream] event in
							multicastStream.send(event)
						}
					)
					state = .streaming(lifecycleTask: task, eventStream: eventStream)
				} catch {
					state = .awaitingSubscribers(lifecycleTask: task)
					print("Failed to create FileSystemEventStream: \(error)")
					// Without this, subscribers hold a stream that never yields and never ends.
					multicastStream.finishAll()
				}
			case .idle:
				state = .idle
				assertionFailure("start() called in unexpected state")
			case .streaming(let task, let eventStream):
				state = .streaming(lifecycleTask: task, eventStream: eventStream)
				assertionFailure("start() called in unexpected state")
			}
		}
	}

	private func stop() {
		state.withLock { state in
			switch consume state {
			case .streaming(let task, _):
				state = .awaitingSubscribers(lifecycleTask: task)
			case .idle:
				state = .idle
				assertionFailure("stop() called in unexpected state")
			case .awaitingSubscribers(let task):
				// Reached when start() failed and finished the streams: the last subscriber
				// goes away while no FSEventStream is running.
				state = .awaitingSubscribers(lifecycleTask: task)
			}
		}
	}

	// MARK: - Static Convenience Methods

	/// Create an `AsyncStream` to monitor file system events.
	///
	/// Each call creates its own `FSEventStream`, monitoring independently of every other stream.
	/// Monitoring stops when the returned stream terminates: when the consumer breaks out of
	/// iteration, cancels its task, or drops the stream without iterating.
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
		precondition(url.isFileURL)
		return makeStream(paths: [url.path], sinceWhen: sinceWhen, latency: latency)
	}

	/// Create an `AsyncStream` to monitor file system events.
	///
	/// Each call creates its own `FSEventStream`, monitoring independently of every other stream.
	/// Monitoring stops when the returned stream terminates: when the consumer breaks out of
	/// iteration, cancels its task, or drops the stream without iterating.
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
		AsyncStream { continuation in
			do {
				let eventStream = try FileSystemEventStream.make(
					paths: paths,
					sinceWhen: sinceWhen,
					latency: latency,
					eventHandler: { event in
						continuation.yield(event)
					}
				)

				// Capturing the box here is what keeps the FSEventStream running: it lives
				// exactly as long as the termination handler, which `AsyncStream` releases
				// once the stream terminates.
				let box = EventStreamBox(eventStream)
				continuation.onTermination = { _ in
					withExtendedLifetime(box) {}
				}
			} catch {
				print("Failed to create FileSystemEventStream: \(error)")
				continuation.finish()
			}
		}
	}
}
