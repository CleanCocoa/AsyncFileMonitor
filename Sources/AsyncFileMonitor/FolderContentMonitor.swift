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
public enum FolderContentMonitor {

	/// Create an `AsyncStream` to monitor file system events.
	///
	/// - Parameters:
	///   - url: The file or directory URL to monitor
	///   - sinceWhen: FSEvent ID to start monitoring from (default: `kFSEventStreamEventIdSinceNow`)
	///   - latency: Event coalescing interval in seconds (default: `0`)
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
	/// - Parameters:
	///   - paths: Array of file or directory paths to monitor
	///   - sinceWhen: FSEvent ID to start monitoring from (default: `kFSEventStreamEventIdSinceNow`)
	///   - latency: Event coalescing interval in seconds (default: `0`)
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
					eventHandler: { batch in
						for event in batch { continuation.yield(event) }
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
