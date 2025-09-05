//
//  TestFileSystemEventStream.swift
//  RaceConditionTests
//
//  Direct copy of FileSystemEventStream for testing that demonstrates
//  even with the actual RAII FSEventStream wrapper and custom executor,
//  Swift concurrency can still cause event reordering under stress.
//

import Foundation

@testable import AsyncFileMonitor

/// Errors that can occur during file system event stream operations.
public enum TestFileSystemEventStreamError: Error {
	case creationFailed
	case startFailed
}

/// Private callback handler for FSEventStream events.
private final class TestEventStreamCallbackHandler {
	weak var eventStream: TestFileSystemEventStream?

	init() {
		self.eventStream = nil
	}

	func handleEvents(
		stream: ConstFSEventStreamRef,
		numEvents: Int,
		eventPaths: UnsafeMutableRawPointer,
		eventFlags: UnsafePointer<FSEventStreamEventFlags>,
		eventIDs: UnsafePointer<FSEventStreamEventId>
	) {
		dispatchPrecondition(condition: .onQueue(TestFileSystemEventExecutor.shared.underlyingQueue))

		guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }

		// Collect events: each FSEvent may be comprised of multiple events we recognize
		var events: [FolderContentChangeEvent] = []
		for index in 0..<numEvents {
			let change = Change(eventFlags: eventFlags[index])
			let event = FolderContentChangeEvent(eventID: eventIDs[index], eventPath: paths[index], change: change)
			events.append(event)
		}

		// Forward events to the event stream
		eventStream?.forward(events: events)
	}
}

private let testEventStreamCallback: FSEventStreamCallback = {
	(stream, contextInfo, numEvents, eventPaths, eventFlags, eventIDs) in
	dispatchPrecondition(condition: .onQueue(TestFileSystemEventExecutor.shared.underlyingQueue))
	guard let contextInfo else { return }
	let handler = Unmanaged<TestEventStreamCallbackHandler>.fromOpaque(contextInfo).takeUnretainedValue()
	handler.handleEvents(
		stream: stream,
		numEvents: numEvents,
		eventPaths: eventPaths,
		eventFlags: eventFlags,
		eventIDs: eventIDs
	)
}

/// Thread-safe RAII wrapper for `FSEventStream` lifecycle management.
///
/// This class handles `FSEventStream` creation, configuration, and cleanup using
/// RAII principles. The deinit can safely run on any thread without assumptions
/// about actor isolation.
final class TestFileSystemEventStream {
	private let streamRef: FSEventStreamRef
	private let queue: DispatchSerialQueue
	private let callbackHandler: TestEventStreamCallbackHandler

	typealias EventHandler = @Sendable (
		_ events: [FolderContentChangeEvent]
	) -> Void

	/// Event handler called when file system events occur.
	private let eventHandler: EventHandler

	/// Creates and starts an FSEventStream with the specified configuration.
	///
	/// - Parameters:
	///   - paths: File system paths to monitor
	///   - sinceWhen: FSEvent ID to start monitoring from
	///   - latency: Event coalescing interval in seconds
	///   - queue: Dispatch queue for FSEventStream callbacks
	/// - Throws: `TestFileSystemEventStreamError` if stream creation fails
	init(
		paths: [String],
		sinceWhen: FSEventStreamEventId,
		latency: CFTimeInterval,
		queue: DispatchSerialQueue,
		eventHandler: @escaping EventHandler
	) throws {
		self.queue = queue
		self.eventHandler = eventHandler
		self.callbackHandler = TestEventStreamCallbackHandler()

		var context = FSEventStreamContext(
			version: 0,
			info: Unmanaged.passUnretained(callbackHandler).toOpaque(),
			retain: nil,
			release: nil,
			copyDescription: nil
		)

		let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)

		guard
			let stream = FSEventStreamCreate(
				kCFAllocatorDefault,
				testEventStreamCallback,
				&context,
				paths as CFArray,
				sinceWhen,
				latency,
				flags
			)
		else {
			throw TestFileSystemEventStreamError.creationFailed
		}

		self.streamRef = stream

		// Now that all properties are initialized, set up the callback handler
		callbackHandler.eventStream = self

		// Configure the stream to use our queue and start monitoring
		FSEventStreamSetDispatchQueue(streamRef, queue)

		guard FSEventStreamStart(streamRef) else {
			FSEventStreamRelease(streamRef)
			throw TestFileSystemEventStreamError.startFailed
		}
	}

	@inlinable
	internal func forward(events: [FolderContentChangeEvent]) {
		eventHandler(events)
	}

	deinit {
		FSEventStreamStop(streamRef)
		FSEventStreamInvalidate(streamRef)
		FSEventStreamRelease(streamRef)
	}
}
