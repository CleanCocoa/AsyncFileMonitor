//
//  FolderContentMonitor.swift
//  AsyncFileMonitor
//
//  Created by Christian Tietze on 08/11/16.
//  Copyright © 2016 Christian Tietze, RxSwiftCommunity (original RxFileMonitor)
//  Copyright © 2025 Christian Tietze (AsyncFileMonitor modernization)
//

import Collections
import Foundation

/// Monitor for a particular file or folder. Change events
/// will fire when the contents of the URL changes:
///
/// If it's a folder, it will fire when you add/remove/rename files or folders
/// below the reference paths. See `Change` for an incomprehensive list of
/// events details that will be reported.

// Manages the shared StreamManager instances
private actor ManagerRegistry {
	static let shared = ManagerRegistry()
	private var managers: [String: StreamManager] = [:]

	func manager(for paths: [String], sinceWhen: FSEventStreamEventId, latency: CFTimeInterval, qos: DispatchQoS)
		-> StreamManager
	{
		let key = paths.sorted().joined(separator: "|")
		if let existing = managers[key] {
			return existing
		}
		let manager = StreamManager(paths: paths, sinceWhen: sinceWhen, latency: latency, qos: qos)
		managers[key] = manager
		return manager
	}

	func removeManager(for paths: [String]) {
		let key = paths.sorted().joined(separator: "|")
		managers.removeValue(forKey: key)
	}
}

public enum FolderContentMonitor {

	/// Create an AsyncStream to monitor file system events.
	///
	/// Each call creates a new independent AsyncStream that shares an underlying FSEventStream for efficiency.
	/// The stream automatically stops when cancelled or deallocated.
	///
	/// - Parameters:
	///   - url: The file or directory URL to monitor
	///   - sinceWhen: Reference event for the subscription. Default is `kFSEventStreamEventIdSinceNow`
	///   - latency: Interval (in seconds) to allow coalescing events. Default is 0
	///   - qos: Quality of service for the monitoring queue. Default is `userInteractive` for UI responsiveness
	/// - Returns: An `AsyncStream` of ``FolderContentChangeEvent`` values.
	public static func makeStream(
		url: URL,
		sinceWhen: FSEventStreamEventId = FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
		latency: CFTimeInterval = 0,
		qos: DispatchQoS = .userInteractive
	) -> AsyncStream<FolderContentChangeEvent> {
		makeStream(
			paths: [url.path],
			sinceWhen: sinceWhen,
			latency: latency,
			qos: qos
		)
	}

	/// Create an AsyncStream to monitor file system events.
	///
	/// Each call creates a new independent AsyncStream that shares an underlying FSEventStream for efficiency.
	/// The stream automatically stops when cancelled or deallocated.
	///
	/// - Parameters:
	///   - paths: Array of file or directory paths to monitor
	///   - sinceWhen: Reference event for the subscription. Default is `kFSEventStreamEventIdSinceNow`
	///   - latency: Interval (in seconds) to allow coalescing events. Default is 0
	///   - qos: Quality of service for the monitoring queue. Default is `userInteractive` for UI responsiveness
	/// - Returns: An `AsyncStream` of ``FolderContentChangeEvent`` values.
	public static func makeStream(
		paths: [String],
		sinceWhen: FSEventStreamEventId = FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
		latency: CFTimeInterval = 0,
		qos: DispatchQoS = .userInteractive
	) -> AsyncStream<FolderContentChangeEvent> {
		AsyncStream { continuation in
			Task {
				let manager = await ManagerRegistry.shared.manager(
					for: paths,
					sinceWhen: sinceWhen,
					latency: latency,
					qos: qos
				)
				await manager.addContinuation(continuation)
			}
		}
	}

	// Internal method for StreamManager to remove itself when no longer needed
	static func removeManager(for paths: [String]) {
		Task {
			await ManagerRegistry.shared.removeManager(for: paths)
		}
	}
}

// StreamManager coordinates multiple streams for the same paths
private actor StreamManager {

	let paths: [String]
	let sinceWhen: FSEventStreamEventId
	let latency: CFTimeInterval
	var streamRef: FSEventStreamRef?

	// Track multiple continuations with OrderedDictionary for simpler management
	private var continuations: OrderedDictionary<Int, AsyncStream<FolderContentChangeEvent>.Continuation> = [:]
	private var nextID: Int = 0

	// Custom queue for FSEventStream operations to work with actor isolation
	private let queue: DispatchSerialQueue
	nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

	init(paths: [String], sinceWhen: FSEventStreamEventId, latency: CFTimeInterval, qos: DispatchQoS) {
		self.paths = paths
		self.sinceWhen = sinceWhen
		self.latency = latency
		self.queue = DispatchSerialQueue(label: "AsyncFileMonitor.StreamManager", qos: qos)
	}

	func addContinuation(_ continuation: AsyncStream<FolderContentChangeEvent>.Continuation) {
		let id = nextID
		nextID += 1
		continuations[id] = continuation

		continuation.onTermination = { _ in
			Task { [weak self] in
				await self?.removeContinuation(id: id)
			}
		}

		// Start monitoring if this is the first stream
		if continuations.count == 1 {
			start()
		}
	}

	private func removeContinuation(id: Int) {
		continuations.removeValue(forKey: id)

		// Stop monitoring if no more streams
		if continuations.isEmpty {
			stop()
			// Remove from shared managers
			FolderContentMonitor.removeManager(for: paths)
		}
	}

	private func start() {
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

			guard let contextInfo else { preconditionFailure("Opaque pointer missing StreamManager") }
			let manager = Unmanaged<StreamManager>.fromOpaque(contextInfo).takeUnretainedValue()

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
			manager.assumeIsolated { $0.handleEvents(events) }
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

	private func stop() {
		guard let streamRef = streamRef else { return }
		FSEventStreamStop(streamRef)
		FSEventStreamInvalidate(streamRef)
		FSEventStreamRelease(streamRef)
		self.streamRef = nil

		// Finish all remaining continuations
		for (_, continuation) in continuations {
			continuation.finish()
		}
		continuations.removeAll()
	}

	private func handleEvents(_ events: [FolderContentChangeEvent]) {
		// Broadcast events to all active continuations
		for (_, continuation) in continuations {
			for event in events {
				continuation.yield(event)
			}
		}
	}
}
