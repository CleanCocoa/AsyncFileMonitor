//
//  FileSystemEventStream.swift
//  AsyncFileMonitor
//
//  RAII wrapper for FSEventStream lifecycle management
//  Reference: 20250905T073442
//
//  Updated to use direct MulticastAsyncStream approach for superior ordering guarantees.
//  Eliminates Swift concurrency Task scheduling that can cause event reordering.
//

import Foundation

/// Errors that can occur during file system event stream operations.
public enum FileSystemEventStreamError: Error {
	case creationFailed
	case startFailed
}

/// Direct FSEventStream callback that sends events immediately to MulticastAsyncStream.
/// This eliminates Swift concurrency Task scheduling and prevents event reordering.
private let directEventStreamCallback: FSEventStreamCallback = {
	(stream, contextInfo, numEvents, eventPaths, eventFlags, eventIDs) in
	guard let contextInfo else { return }
	guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }

	// Extract the MulticastAsyncStream from the context
	let multicastStream = Unmanaged<MulticastAsyncStream<FolderContentChangeEvent>>.fromOpaque(contextInfo)
		.takeUnretainedValue()

	// Process events directly - no Task scheduling, no actor isolation
	for index in 0..<numEvents {
		let change = Change(eventFlags: eventFlags[index])
		let event = FolderContentChangeEvent(eventID: eventIDs[index], eventPath: paths[index], change: change)
		multicastStream.send(event)
	}
}

/// Thread-safe RAII wrapper for `FSEventStream` lifecycle management.
///
/// This class handles `FSEventStream` creation, configuration, and cleanup using
/// RAII principles. Uses direct MulticastAsyncStream approach for superior event ordering.
final class FileSystemEventStream {
	private let streamRef: FSEventStreamRef
	private let queue: DispatchQueue
	private let multicastStream: MulticastAsyncStream<FolderContentChangeEvent>

	/// Creates and starts an FSEventStream with the specified configuration.
	///
	/// - Parameters:
	///   - paths: File system paths to monitor
	///   - sinceWhen: FSEvent ID to start monitoring from
	///   - latency: Event coalescing interval in seconds
	///   - multicastStream: MulticastAsyncStream to send events to directly
	/// - Throws: `FileSystemEventStreamError` if stream creation fails
	init(
		paths: [String],
		sinceWhen: FSEventStreamEventId,
		latency: CFTimeInterval,
		multicastStream: MulticastAsyncStream<FolderContentChangeEvent>
	) throws {
		self.queue = DispatchQueue(label: "FileSystemEventStream", qos: .userInteractive)
		self.multicastStream = multicastStream

		// Create the callback context - pass the MulticastAsyncStream as the context
		let contextPointer = Unmanaged.passUnretained(multicastStream).toOpaque()
		var context = FSEventStreamContext(
			version: 0,
			info: contextPointer,
			retain: nil,
			release: nil,
			copyDescription: nil
		)

		let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)

		guard
			let stream = FSEventStreamCreate(
				kCFAllocatorDefault,
				directEventStreamCallback,
				&context,
				paths as CFArray,
				sinceWhen,
				latency,
				flags
			)
		else {
			throw FileSystemEventStreamError.creationFailed
		}

		self.streamRef = stream

		// Configure the stream to use our queue and start monitoring
		FSEventStreamSetDispatchQueue(streamRef, queue)

		guard FSEventStreamStart(streamRef) else {
			FSEventStreamRelease(streamRef)
			throw FileSystemEventStreamError.startFailed
		}
	}

	deinit {
		FSEventStreamStop(streamRef)
		FSEventStreamInvalidate(streamRef)
		FSEventStreamRelease(streamRef)
	}
}
