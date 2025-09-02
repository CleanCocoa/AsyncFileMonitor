//
//  FolderContentMonitor.swift
//  AsyncFileMonitor
//
//  Created by Christian Tietze on 08/11/16.
//  Copyright © 2016 Christian Tietze, RxSwiftCommunity (original RxFileMonitor)
//  Copyright © 2025 Christian Tietze (AsyncFileMonitor modernization)
//

import Foundation

/// Monitor for a particular file or folder. Change events
/// will fire when the contents of the URL changes:
///
/// If it's a folder, it will fire when you add/remove/rename files or folders
/// below the reference paths. See `Change` for an incomprehensive list of
/// events details that will be reported.
public final class FolderContentMonitor {

	/// Create an AsyncStream to monitor file system events.
	///
	/// Each call creates a new independent FSEventStream that monitors the specified paths.
	/// The stream automatically stops when cancelled or deallocated.
	///
	/// - Parameters:
	///   - url: The file or directory URL to monitor
	///   - sinceWhen: Reference event for the subscription. Default is `kFSEventStreamEventIdSinceNow`
	///   - latency: Interval (in seconds) to allow coalescing events. Default is 0
	///   - qos: Quality of service for the monitoring queue. Default is `userInteractive` for UI responsiveness
	/// - Returns: An `AsyncStream` of ``FolderContentChangeEvent`` values.
	public static func monitor(
		url: URL,
		sinceWhen: FSEventStreamEventId = FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
		latency: CFTimeInterval = 0,
		qos: DispatchQoS = .userInteractive
	) -> AsyncStream<FolderContentChangeEvent> {
		monitor(
			paths: [url.path],
			sinceWhen: sinceWhen,
			latency: latency,
			qos: qos
		)
	}

	/// Create an AsyncStream to monitor file system events.
	///
	/// Each call creates a new independent FSEventStream that monitors the specified paths.
	/// The stream automatically stops when cancelled or deallocated.
	///
	/// - Parameters:
	///   - paths: Array of file or directory paths to monitor
	///   - sinceWhen: Reference event for the subscription. Default is `kFSEventStreamEventIdSinceNow`
	///   - latency: Interval (in seconds) to allow coalescing events. Default is 0
	///   - qos: Quality of service for the monitoring queue. Default is `userInteractive` for UI responsiveness
	/// - Returns: An `AsyncStream` of ``FolderContentChangeEvent`` values.
	public static func monitor(
		paths: [String],
		sinceWhen: FSEventStreamEventId = FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
		latency: CFTimeInterval = 0,
		qos: DispatchQoS = .userInteractive
	) -> AsyncStream<FolderContentChangeEvent> {
		AsyncStream { continuation in
			let streamHandler = StreamHandler(
				paths: paths,
				sinceWhen: sinceWhen,
				latency: latency,
				continuation: continuation,
				qos: qos
			)

			continuation.onTermination = { _ in
				Task { await streamHandler.stop() }
			}

			Task {
				await streamHandler.start()
			}
		}
	}
}

// Private actor that manages a single FSEventStream and its continuation.
//
// Uses a custom `SerialExecutor` with configurable queue priority. The default queue priority of
// `.userInteractive` is picked for UI responsiveness.
private actor StreamHandler {
	let paths: [String]
	let sinceWhen: FSEventStreamEventId
	let latency: CFTimeInterval
	let continuation: AsyncStream<FolderContentChangeEvent>.Continuation
	var streamRef: FSEventStreamRef?

	// Custom queue for FSEventStream operations to work with actor isolation
	private let queue: DispatchSerialQueue
	nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

	init(
		paths: [String],
		sinceWhen: FSEventStreamEventId,
		latency: CFTimeInterval,
		continuation: AsyncStream<FolderContentChangeEvent>.Continuation,
		qos: DispatchQoS = .userInteractive
	) {
		self.paths = paths
		self.sinceWhen = sinceWhen
		self.latency = latency
		self.continuation = continuation
		self.queue = DispatchSerialQueue(label: "AsyncFileMonitor.StreamHandler", qos: qos)
	}

	deinit {
		continuation.finish()
	}

	func start() {
		guard streamRef == nil else { return }

		// Define the callback inline to avoid global state
		let callback: FSEventStreamCallback = {
			(
				stream: ConstFSEventStreamRef,
				contextInfo: UnsafeMutableRawPointer?,
				numEvents: Int,
				eventPaths: UnsafeMutableRawPointer,
				eventFlags: UnsafePointer<FSEventStreamEventFlags>,
				eventIDs: UnsafePointer<FSEventStreamEventId>
			) in

			guard let contextInfo else { preconditionFailure("Opaque pointer missing StreamHandler") }
			let handler = Unmanaged<StreamHandler>.fromOpaque(contextInfo).takeUnretainedValue()

			guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }

			// Collect events: each FSEvent may be comprised of multiple events we recognize
			var events: [FolderContentChangeEvent] = []
			for index in 0..<numEvents {
				let change = Change(eventFlags: eventFlags[index])
				let event = FolderContentChangeEvent(eventID: eventIDs[index], eventPath: paths[index], change: change)
				events.append(event)
			}

			// We configure FSEventStreamSetDispatchQueue to use the same queue as the actor itself
			// uses for its SerialExecutor.
			handler.assumeIsolated { $0.handleEvents(events) }
		}

		var context = FSEventStreamContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
		context.info = Unmanaged.passUnretained(self).toOpaque()

		let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
		streamRef = FSEventStreamCreate(
			kCFAllocatorDefault,
			callback,
			&context,
			paths as CFArray,
			sinceWhen,
			latency,
			flags
		)

		guard let streamRef else { return }

		FSEventStreamSetDispatchQueue(streamRef, queue)  // Share the serial execution queue used for actor isolation
		FSEventStreamStart(streamRef)
	}

	func stop() {
		guard let streamRef else { return }
		FSEventStreamStop(streamRef)
		FSEventStreamInvalidate(streamRef)
		FSEventStreamRelease(streamRef)
	}

	func handleEvents(_ events: [FolderContentChangeEvent]) {
		for event in events {
			continuation.yield(event)
		}
	}
}
