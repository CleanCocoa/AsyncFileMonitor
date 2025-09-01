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
public final class FolderContentMonitor: @unchecked Sendable {

	public let pathsToWatch: [String]
	public let latency: CFTimeInterval
	public private(set) var lastEventId: FSEventStreamEventId

	private var streamRef: FSEventStreamRef?
	private var continuations: Set<ContinuationWrapper> = []
	private let continuationsLock = NSLock()

	private final class ContinuationWrapper: @unchecked Sendable, Hashable {
		let id = UUID()
		let continuation: AsyncStream<FolderContentChangeEvent>.Continuation

		init(_ continuation: AsyncStream<FolderContentChangeEvent>.Continuation) {
			self.continuation = continuation
		}

		func hash(into hasher: inout Hasher) {
			hasher.combine(id)
		}

		static func == (lhs: ContinuationWrapper, rhs: ContinuationWrapper) -> Bool {
			lhs.id == rhs.id
		}
	}

	/// - parameter url: Folder to monitor.
	/// - parameter sinceWhen: Reference event for the subscription. Default
	///   is `kFSEventStreamEventIdSinceNow`.
	/// - parameter latency: Interval (in seconds) to allow coalescing events.
	public convenience init(
		url: URL,
		sinceWhen: FSEventStreamEventId = FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
		latency: CFTimeInterval = 0
	) {
		self.init(
			pathsToWatch: [url.path],
			sinceWhen: sinceWhen,
			latency: latency
		)
	}

	/// - parameter pathsToWatch: Collection of file or folder paths.
	/// - parameter sinceWhen: Reference event for the subscription. Default
	///   is `kFSEventStreamEventIdSinceNow`.
	/// - parameter latency: Interval (in seconds) to allow coalescing events.
	public init(
		pathsToWatch: [String],
		sinceWhen: FSEventStreamEventId = FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
		latency: CFTimeInterval = 0
	) {
		self.lastEventId = sinceWhen
		self.pathsToWatch = pathsToWatch
		self.latency = latency
	}

	deinit {
		stop()
	}

	/// Create an AsyncStream to monitor file system events.
	///
	/// This method starts monitoring and returns an AsyncStream that yields
	/// file system events. Multiple streams can be created from the same monitor,
	/// and they will all receive the same events. The monitoring automatically
	/// stops when all streams are cancelled or deallocated.
	///
	/// - Returns: An AsyncStream of FolderContentChangeEvent objects
	public func makeAsyncStream() -> AsyncStream<FolderContentChangeEvent> {
		AsyncStream { continuation in
			let wrapper = ContinuationWrapper(continuation)

			self.continuationsLock.lock()
			self.continuations.insert(wrapper)
			self.continuationsLock.unlock()

			// Ensure monitoring is started (safe to call multiple times)
			self.start()

			// Handle cancellation
			continuation.onTermination = { @Sendable [weak self] _ in
				self?.removeContinuation(wrapper)
			}
		}
	}

	private func removeContinuation(_ wrapper: ContinuationWrapper) {
		continuationsLock.lock()
		continuations.remove(wrapper)
		let shouldStop = continuations.isEmpty
		continuationsLock.unlock()

		// Stop monitoring if no more streams are active
		if shouldStop {
			stop()
		}
	}

	/// Start file system monitoring. Safe to call multiple times - will only start once.
	private func start() {
		guard streamRef == nil else { return }

		var context = FSEventStreamContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
		context.info = Unmanaged.passUnretained(self).toOpaque()
		let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
		streamRef = FSEventStreamCreate(
			kCFAllocatorDefault,
			eventCallback,
			&context,
			pathsToWatch as CFArray,
			lastEventId,
			latency,
			flags
		)

		guard let streamRef = streamRef else { return }

		FSEventStreamSetDispatchQueue(streamRef, DispatchQueue.main)
		FSEventStreamStart(streamRef)
	}

	private let eventCallback: FSEventStreamCallback = {
		(
			stream: ConstFSEventStreamRef,
			contextInfo: UnsafeMutableRawPointer?,
			numEvents: Int,
			eventPaths: UnsafeMutableRawPointer,
			eventFlags: UnsafePointer<FSEventStreamEventFlags>,
			eventIds: UnsafePointer<FSEventStreamEventId>
		) in

		let fileSystemWatcher: FolderContentMonitor = unsafeBitCast(contextInfo, to: FolderContentMonitor.self)

		guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String]
		else { return }

		// Get all active continuations
		fileSystemWatcher.continuationsLock.lock()
		let activeContinuations = Array(fileSystemWatcher.continuations)
		fileSystemWatcher.continuationsLock.unlock()

		// Distribute events to all active streams
		for index in 0..<numEvents {
			let change = Change(eventFlags: eventFlags[index])
			let event = FolderContentChangeEvent(eventId: eventIds[index], eventPath: paths[index], change: change)

			for wrapper in activeContinuations {
				wrapper.continuation.yield(event)
			}
		}

		fileSystemWatcher.lastEventId = eventIds[numEvents - 1]
	}

	private func stop() {
		guard let streamRef = streamRef else { return }

		FSEventStreamStop(streamRef)
		FSEventStreamInvalidate(streamRef)
		FSEventStreamRelease(streamRef)
		self.streamRef = nil

		// Finish all active continuations
		continuationsLock.lock()
		let activeContinuations = Array(continuations)
		continuations.removeAll()
		continuationsLock.unlock()

		for wrapper in activeContinuations {
			wrapper.continuation.finish()
		}
	}
}
