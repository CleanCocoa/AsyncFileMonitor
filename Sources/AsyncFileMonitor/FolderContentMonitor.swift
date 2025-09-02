//
//  FolderContentMonitor.swift
//  AsyncFileMonitor
//
//  Created by Christian Tietze on 08/11/16.
//  Copyright © 2016 Christian Tietze, RxSwiftCommunity (original RxFileMonitor)
//  Copyright © 2025 Christian Tietze (AsyncFileMonitor modernization)
//

import Foundation

/// Monitor for a particular file or folder.
///
/// ``Change`` events will fire when the contents of the URL changes. If the monitored path is a
/// folder, it will fire when you add/remove/rename files or folders below the reference paths.
///
/// See ``Change`` for an incomprehensive list of events details that will be reported.
public actor FolderContentMonitor {
	fileprivate let registrar = StreamRegistrar<FolderContentChangeEvent>()
	fileprivate var streamRef: FSEventStreamRef?

	/// The paths being monitored.
	public let paths: [String]

	/// The latency setting for event coalescing.
	public let latency: CFTimeInterval

	/// The FSEventStreamEventId to start from.
	public let sinceWhen: FSEventStreamEventId

	// Custom queue for FSEventStream operations to work with actor isolation
	fileprivate let queue: DispatchSerialQueue
	nonisolated public var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

	private var registrarLifecycle: Task<Void, Never>?

	/// Create a new monitor for the specified paths.
	public init(
		paths: [String],
		sinceWhen: FSEventStreamEventId = FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
		latency: CFTimeInterval = 0,
		qos: DispatchQoS = .userInteractive
	) {
		self.paths = paths
		self.latency = latency
		self.sinceWhen = sinceWhen
		self.queue = DispatchSerialQueue(label: "AsyncFileMonitor.FolderContentMonitor", qos: qos)
		self.registrarLifecycle = nil
	}

	/// Create a new monitor for a single URL.
	public init(
		url: URL,
		sinceWhen: FSEventStreamEventId = FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
		latency: CFTimeInterval = 0,
		qos: DispatchQoS = .userInteractive
	) {
		precondition(url.isFileURL)
		self.init(
			paths: [url.path],
			sinceWhen: sinceWhen,
			latency: latency,
			qos: qos
		)
	}

	deinit {
		assumeIsolated { actor in
			if let streamRef = actor.streamRef {
				FSEventStreamStop(streamRef)
				FSEventStreamInvalidate(streamRef)
				FSEventStreamRelease(streamRef)
			}
			actor.registrarLifecycle?.cancel()
		}
	}

	/// Create a new `AsyncStream` of change events for this monitor.
	///
	/// Multiple streams can be created from the same monitor instance.
	public func makeStream() async -> AsyncStream<FolderContentChangeEvent> {
		await setupLifecycleManagement()
		return await registrar.makeStream()
	}

	/// Set up automatic start/stop lifecycle management based on stream count.
	private func setupLifecycleManagement() async {
		guard registrarLifecycle == nil else { return }

		// Set up the lifecycle stream first to avoid race condition
		let lifecycleEvents = await registrar.makeLifecycleStream()

		registrarLifecycle = Task {
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
		guard streamRef == nil else { return }

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
	}

	// MARK: - Static Convenience Methods

	/// Create an `AsyncStream` to monitor file system events.
	///
	/// This creates a new ``FolderContentMonitor`` instance and returns its first stream.
	/// The monitor will be kept alive as long as the stream is active.
	nonisolated public static func makeStream(
		url: URL,
		sinceWhen: FSEventStreamEventId = FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
		latency: CFTimeInterval = 0,
		qos: DispatchQoS = .userInteractive
	) -> AsyncStream<FolderContentChangeEvent> {
		let monitor = FolderContentMonitor(
			url: url,
			sinceWhen: sinceWhen,
			latency: latency,
			qos: qos
		)

		// Keep monitor alive as long as stream is active
		return AsyncStream { continuation in
			Task {
				let stream = await monitor.makeStream()
				for await event in stream {
					continuation.yield(event)
				}
				continuation.finish()
				// Monitor will be deallocated when stream ends
				_ = monitor
			}
		}
	}

	/// Create an AsyncStream to monitor file system events.
	///
	/// This creates a new FolderContentMonitor instance and returns its first stream.
	/// The monitor will be kept alive as long as the stream is active.
	nonisolated public static func makeStream(
		paths: [String],
		sinceWhen: FSEventStreamEventId = FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
		latency: CFTimeInterval = 0,
		qos: DispatchQoS = .userInteractive
	) -> AsyncStream<FolderContentChangeEvent> {
		let monitor = FolderContentMonitor(
			paths: paths,
			sinceWhen: sinceWhen,
			latency: latency,
			qos: qos
		)

		// Keep monitor alive as long as stream is active
		return AsyncStream { continuation in
			Task {
				let stream = await monitor.makeStream()
				for await event in stream {
					continuation.yield(event)
				}
				continuation.finish()
				// Monitor will be deallocated when stream ends
				_ = monitor
			}
		}
	}
}

private let callback: FSEventStreamCallback = {
	(
		stream: ConstFSEventStreamRef,
		contextInfo: UnsafeMutableRawPointer?,
		numEvents: Int,
		eventPaths: UnsafeMutableRawPointer,
		eventFlags: UnsafePointer<FSEventStreamEventFlags>,
		eventIDs: UnsafePointer<FSEventStreamEventId>
	) in

	guard let contextInfo else { preconditionFailure("Opaque pointer missing FolderContentMonitor") }
	let monitor = Unmanaged<FolderContentMonitor>.fromOpaque(contextInfo).takeUnretainedValue()

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
	_ = monitor.assumeIsolated { actor in
		Task {
			for event in events {
				await actor.registrar.yield(event)
			}
		}
	}
}
