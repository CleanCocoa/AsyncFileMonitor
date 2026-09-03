//
//  FolderContentMonitor.swift
//  AsyncFileMonitor
//
//  Created by Christian Tietze on 08/11/16.
//  Copyright © 2016 Christian Tietze, RxSwiftCommunity (original RxFileMonitor)
//  Copyright © 2025 Christian Tietze (AsyncFileMonitor modernization)
//

import Foundation

/// Namespace for the factories that monitor a file or folder for changes.
///
/// ``Change`` events fire when the contents of a monitored path change. If the path is a folder,
/// events fire when files or folders below it are added, removed or renamed. See ``Change`` for
/// what is reported, and ``StreamCondition`` for what the stream reports about itself.
///
/// ```swift
/// for await event in FolderContentMonitor.makeStream(url: myFolderURL) {
///     print("Change detected: \(event.eventPath)")
/// }
/// ```
///
/// Each stream owns its own `FSEventStream`, created synchronously when the factory returns and
/// torn down when the stream terminates — whether the consumer breaks out of iteration, cancels
/// its task, or drops the stream without iterating.
///
/// Because creation is synchronous, the factories throw rather than handing back a stream that
/// never yields: a stream you hold is a stream that started. Nothing but consumer teardown ends
/// one, so a finished stream is never an unreported failure.
public enum FolderContentMonitor {

	/// Why monitoring could not start.
	///
	/// FSEvents can only fail while the stream is being set up, never once it is running, so
	/// this is thrown by the factories and never delivered as an event.
	public enum Error: Swift.Error {
		/// `FSEventStreamCreate` returned no stream, which happens only for an invalid argument.
		case creationFailed

		/// `FSEventStreamStart` refused to start the stream.
		///
		/// Apple documents this as something that "ought to always succeed"; if it does not,
		/// the recommended fallback is to scan the directories yourself.
		case startFailed

		init(_ error: FileSystemEventStream.Error) {
			switch error {
			case .creationFailed: self = .creationFailed
			case .startFailed: self = .startFailed
			}
		}
	}

	/// Create an `AsyncStream` to monitor file system events.
	///
	/// - Parameters:
	///   - url: The file or directory URL to monitor
	///   - sinceWhen: FSEvent ID to start monitoring from (default: `kFSEventStreamEventIdSinceNow`)
	///   - latency: Event coalescing interval in seconds (default: `0`)
	public static func makeStream(
		url: URL,
		configuration: Configuration = Configuration()
	) throws(Error) -> AsyncStream<FolderContentChangeEvent> {
		precondition(url.isFileURL)
		return try makeStream(paths: [url.path], configuration: configuration)
	}

	/// Create an `AsyncStream` to monitor file system events.
	///
	/// - Parameters:
	///   - paths: Array of file or directory paths to monitor
	///   - sinceWhen: FSEvent ID to start monitoring from (default: `kFSEventStreamEventIdSinceNow`)
	///   - latency: Event coalescing interval in seconds (default: `0`)
	public static func makeStream(
		paths: [String],
		configuration: Configuration = Configuration()
	) throws(Error) -> AsyncStream<FolderContentChangeEvent> {
		try makeStream(paths: paths, configuration: configuration) { batch, continuation in
			for event in batch { continuation.yield(event) }
		}
	}

	/// Create an `AsyncStream` delivering one FSEvents callback's worth of events at a time.
	///
	/// FSEvents groups related changes: an atomic save arrives as a single callback naming the
	/// temporary file, the final file and the metadata changes the OS made along the way. Use
	/// this form when that grouping matters; use ``makeStream(url:sinceWhen:latency:)`` when it
	/// does not.
	///
	/// Batches are never empty, and ``StreamCondition`` elements appear in them at the position
	/// FSEvents produced them — a change reported after ``StreamCondition/mustScanSubDirectories``
	/// survives the rescan it demands, one reported before it does not.
	///
	/// - Parameters:
	///   - url: The file or directory URL to monitor
	///   - sinceWhen: FSEvent ID to start monitoring from (default: `kFSEventStreamEventIdSinceNow`)
	///   - latency: Event coalescing interval in seconds (default: `0`)
	public static func makeBatchedStream(
		url: URL,
		configuration: Configuration = Configuration()
	) throws(Error) -> AsyncStream<[FolderContentChangeEvent]> {
		precondition(url.isFileURL)
		return try makeBatchedStream(paths: [url.path], configuration: configuration)
	}

	/// Create an `AsyncStream` delivering one FSEvents callback's worth of events at a time.
	///
	/// See ``makeBatchedStream(url:sinceWhen:latency:)`` for when to prefer this over the
	/// per-event form.
	///
	/// - Parameters:
	///   - paths: Array of file or directory paths to monitor
	///   - sinceWhen: FSEvent ID to start monitoring from (default: `kFSEventStreamEventIdSinceNow`)
	///   - latency: Event coalescing interval in seconds (default: `0`)
	public static func makeBatchedStream(
		paths: [String],
		configuration: Configuration = Configuration()
	) throws(Error) -> AsyncStream<[FolderContentChangeEvent]> {
		try makeStream(paths: paths, configuration: configuration) { batch, continuation in
			continuation.yield(batch)
		}
	}

	/// Bridges one `FSEventStream` to one `AsyncStream`, leaving the element shape to `deliver`.
	///
	/// Both public shapes go through here so the RAII wiring exists once. `deliver` runs on the
	/// stream's dispatch queue and must not hop to a `Task`: that boundary is where Swift
	/// concurrency could reorder events FSEvents delivered in order.
	private static func makeStream<Element: Sendable>(
		paths: [String],
		configuration: Configuration,
		deliver: @escaping @Sendable ([FolderContentChangeEvent], AsyncStream<Element>.Continuation) -> Void
	) throws(Error) -> AsyncStream<Element> {
		let (stream, continuation) = AsyncStream<Element>.makeStream()
		do {
			let eventStream = try FileSystemEventStream.make(
				paths: paths,
				configuration: configuration,
				eventHandler: { batch in deliver(batch, continuation) }
			)

			// Capturing the box here is what keeps the FSEventStream running: it lives
			// exactly as long as the termination handler, which `AsyncStream` releases
			// once the stream terminates.
			let box = EventStreamBox(eventStream)
			continuation.onTermination = { _ in
				withExtendedLifetime(box) {}
			}
			return stream
		} catch {
			throw Error(error)
		}
	}
}
