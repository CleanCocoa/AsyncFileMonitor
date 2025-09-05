//
//  FileSystemEventStream.swift
//  AsyncFileMonitor
//
//  Created by Christian Tietze on 2025-09-05.
//  Copyright © 2025 Christian Tietze (AsyncFileMonitor modernization)
//
//  Reference: 20250905T073442
//
//  Pure RAII wrapper that manages FSEventStream lifecycle with event handler injection.
//

import Foundation

/// Errors that can occur during file system event stream operations.
public enum FileSystemEventStreamError: Error {
	/// `FSEventStreamCreate` can only fail with an invalid pointer, which is an irrecoverable situation.
	case creationFailed
	/// `FSEventStreamStart` "ought to always succeed" (see docs), but if it doesn't, it's recommended you scan directories recursively yourself.
	case startFailed
}

/// Container for the event handler closure to pass through FSEventStream context.
///
/// This approach is cleaner than self-references because it avoids the complexity
/// of Swift's initialization requirements when passing `self` to C callbacks.
/// The box pattern allows clean separation between the RAII wrapper and the callback context.
private final class EventHandlerBox {
	let handler: @Sendable (FolderContentChangeEvent) -> Void

	init(handler: @escaping @Sendable (FolderContentChangeEvent) -> Void) {
		self.handler = handler
	}
}

/// Direct FSEventStream callback that forwards events to the provided handler.
/// This eliminates Swift concurrency Task scheduling and prevents event reordering.
private let directEventStreamCallback: FSEventStreamCallback = {
	(stream, contextInfo, numEvents, eventPaths, eventFlags, eventIDs) in
	guard let contextInfo else { return }
	guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }

	// Extract the event handler from the context
	let eventHandler = Unmanaged<EventHandlerBox>.fromOpaque(contextInfo)
		.takeUnretainedValue().handler

	// Process events directly - no Task scheduling, no actor isolation
	for index in 0..<numEvents {
		let change = Change(eventFlags: eventFlags[index])
		let event = FolderContentChangeEvent(eventID: eventIDs[index], eventPath: paths[index], change: change)
		eventHandler(event)
	}
}

/// Thread-safe RAII wrapper for `FSEventStream` lifecycle management.
///
/// This class handles `FSEventStream` creation, configuration, and cleanup using
/// RAII principles. Events are forwarded to the provided handler closure.
/// The FileSystemEventStream has exactly one "port" - the event handler closure.
final class FileSystemEventStream {
	private let streamRef: FSEventStreamRef
	private let queue: DispatchQueue
	private let eventHandlerBox: EventHandlerBox

	/// Creates and starts an FSEventStream with the specified configuration.
	///
	/// - Parameters:
	///   - paths: File system paths to monitor
	///   - sinceWhen: FSEvent ID to start monitoring from
	///   - latency: Event coalescing interval in seconds
	///   - eventHandler: Sendable closure to handle events
	/// - Throws: `FileSystemEventStreamError` if stream creation fails
	init(
		paths: [String],
		sinceWhen: FSEventStreamEventId,
		latency: CFTimeInterval,
		eventHandler: @escaping @Sendable (FolderContentChangeEvent) -> Void
	) throws {
		self.queue = DispatchQueue(label: "FileSystemEventStream", qos: .userInteractive)
		self.eventHandlerBox = EventHandlerBox(handler: eventHandler)

		// Create the callback context - pass the event handler box as the context
		let contextPointer = Unmanaged.passUnretained(eventHandlerBox).toOpaque()
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
			// The fact that FSEventStreamCreate returns an Optional<OpaquePointer> could simply be a Swift API translation artifact. When this fails, we might as well crash the app.
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
