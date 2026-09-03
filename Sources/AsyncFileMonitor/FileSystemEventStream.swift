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
import Synchronization

/// Thread-safe RAII wrapper for `FSEventStream` lifecycle management.
///
/// This class handles `FSEventStream` creation, configuration, and cleanup using
/// RAII principles. Events are forwarded to the provided handler closure.
/// The FileSystemEventStream has exactly one "port" - the event handler closure.
struct FileSystemEventStream: ~Copyable {
	/// Number of `FSEventStream`s that have started and not yet been released.
	///
	/// Only tests read this; it is the one observable proof that teardown reaches the kernel
	/// stream rather than merely dropping the Swift wrapper.
	static let liveCount = Atomic<Int>(0)

	/// Errors that can occur while creating a file system event stream.
	enum Error: Swift.Error {
		/// `FSEventStreamCreate` can only fail with an invalid pointer, which is an irrecoverable situation.
		case creationFailed
		/// `FSEventStreamStart` "ought to always succeed" (see docs), but if it doesn't, it's recommended you scan directories recursively yourself.
		case startFailed
	}

	/// Carries the event handler through the `FSEventStreamContext`, which can only hold an
	/// opaque pointer.
	private final class EventHandlerBox: Sendable {
		let handler: @Sendable ([FolderContentChangeEvent]) -> Void

		init(handler: @escaping @Sendable ([FolderContentChangeEvent]) -> Void) {
			self.handler = handler
		}
	}

	/// Forwards one callback's worth of events to the handler on the stream's dispatch queue.
	///
	/// The batch is delivered whole because FSEvents' coalescing boundary is meaningful: an
	/// atomic save arrives as one callback naming several paths. Flattening here would discard
	/// it before any consumer could see it.
	///
	/// Deliberately free of Task hops: scheduling here would let Swift concurrency reorder
	/// events that FSEvents delivered in order.
	private static let eventStreamCallback: FSEventStreamCallback = {
		(stream, contextInfo, numEvents, eventPaths, eventFlags, eventIDs) in
		guard let contextInfo else { return }
		guard let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as NSArray as? [String]
		else {
			return
		}

		let eventHandler = Unmanaged<EventHandlerBox>.fromOpaque(contextInfo)
			.takeUnretainedValue().handler

		var batch: [FolderContentChangeEvent] = []
		batch.reserveCapacity(numEvents)
		for index in 0..<numEvents {
			let flags = eventFlags[index]
			batch.append(
				FolderContentChangeEvent(
					eventID: eventIDs[index],
					eventPath: paths[index],
					change: Change(eventFlags: flags),
					condition: StreamCondition(eventFlags: flags)
				)
			)
		}
		eventHandler(batch)
	}

	private let streamRef: FSEventStreamRef
	private let queue: DispatchQueue
	private let eventHandlerBox: EventHandlerBox

	private init(streamRef: FSEventStreamRef, queue: DispatchQueue, eventHandlerBox: EventHandlerBox) {
		self.streamRef = streamRef
		self.queue = queue
		self.eventHandlerBox = eventHandlerBox
	}

	/// Creates and starts an FSEventStream with the specified configuration.
	///
	/// - Parameters:
	///   - paths: File system paths to monitor
	///   - sinceWhen: FSEvent ID to start monitoring from
	///   - latency: Event coalescing interval in seconds
	///   - eventHandler: Sendable closure receiving one FSEvents callback's worth of events
	/// - Throws: ``FileSystemEventStream/Error`` if stream creation or start fails
	static func make(
		paths: [String],
		sinceWhen: FSEventStreamEventId,
		latency: CFTimeInterval,
		eventHandler: @escaping @Sendable ([FolderContentChangeEvent]) -> Void
	) throws(FileSystemEventStream.Error) -> FileSystemEventStream {
		let queue = DispatchQueue(label: "FileSystemEventStream", qos: .userInteractive)
		let eventHandlerBox = EventHandlerBox(handler: eventHandler)

		let contextPointer = Unmanaged.passUnretained(eventHandlerBox).toOpaque()
		var context = FSEventStreamContext(
			version: 0,
			info: contextPointer,
			retain: { info -> UnsafeRawPointer? in
				guard let info else { return nil }
				return UnsafeRawPointer(Unmanaged<EventHandlerBox>.fromOpaque(info).retain().toOpaque())
			},
			release: { info in
				guard let info else { return }
				Unmanaged<EventHandlerBox>.fromOpaque(info).release()
			},
			copyDescription: nil
		)

		let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)

		guard
			let stream = FSEventStreamCreate(
				kCFAllocatorDefault,
				eventStreamCallback,
				&context,
				paths as CFArray,
				sinceWhen,
				latency,
				flags
			)
		else {
			throw Error.creationFailed
		}

		FSEventStreamSetDispatchQueue(stream, queue)

		guard FSEventStreamStart(stream) else {
			FSEventStreamRelease(stream)
			throw Error.startFailed
		}

		liveCount.add(1, ordering: .relaxed)
		return FileSystemEventStream(streamRef: stream, queue: queue, eventHandlerBox: eventHandlerBox)
	}

	deinit {
		FileSystemEventStream.liveCount.subtract(1, ordering: .relaxed)
		FSEventStreamStop(streamRef)
		FSEventStreamInvalidate(streamRef)
		FSEventStreamRelease(streamRef)
	}
}

/// Reference-typed holder that keeps a started ``FileSystemEventStream`` alive.
///
/// ``FileSystemEventStream`` is non-copyable and cannot be captured by an escaping closure
/// directly. Boxing it hands the closure an ordinary reference to hold instead; the stream is
/// stopped and released when the last reference to the box goes away.
///
/// - Warning: `deinit` runs on whichever thread releases the box, and `FSEventStreamStop`
///   blocks until in-flight callbacks on the stream's dispatch queue have returned. Releasing
///   the last reference from that queue — i.e. from inside an event handler — deadlocks.
final class EventStreamBox: @unchecked Sendable {
	private let eventStream: FileSystemEventStream

	init(_ eventStream: consuming FileSystemEventStream) {
		self.eventStream = eventStream
	}
}
