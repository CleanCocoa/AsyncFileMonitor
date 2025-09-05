//
// DirectAsyncStream.swift
// RaceConditionTests
//
// Swift Testing implementation examining a direct AsyncStream approach to file
// system monitoring. This approach bypasses actors entirely, using AsyncStream.Continuation
// directly from FSEventStream callbacks to test if we can achieve better ordering
// guarantees by eliminating Swift concurrency Task scheduling.
//
// Reference: 20250905T073442
//

import Foundation
import OrderedCollections
import Synchronization
import Testing

@testable import AsyncFileMonitor

// MARK: - Direct AsyncStream Baseline Tests

@Test("Direct AsyncStream maintains order under moderate load")
func directAsyncStreamModerateLoad() async throws {
	let events = try await runDirectStreamTest(
		filePrefix: "moderate",
		fileCount: 25,
		creationDelay: 8_000_000  // 8ms - allows proper ordering
	)

	#expect(events.count > 0, "Should receive file creation events")

	let isChronological = areEventsChronological(events)
	#expect(
		isChronological,
		"Direct AsyncStream should maintain perfect order under moderate load. Got \(events.count) events with ordering score: \(Int(calculateOrderingScore(received: events.map { $0.filename }, expected: events.map { $0.filename }.sorted()) * 100))%"
	)
}

@Test("Direct AsyncStream maintains order even under high stress")
func directAsyncStreamHighStress() async throws {
	let events = try await runDirectStreamTest(
		filePrefix: "stress",
		fileCount: 100,
		creationDelay: 1_000_000  // 1ms - minimal delay to maximize stress
	)

	#expect(events.count > 0, "Should receive file creation events")

	let isChronological = areEventsChronological(events)
	#expect(
		isChronological,
		"Direct AsyncStream should maintain order even under high stress. Got \(events.count) events with ordering score: \(Int(calculateOrderingScore(received: events.map { $0.filename }, expected: events.map { $0.filename }.sorted()) * 100))%"
	)
}

// MARK: - Helper Functions

/// Run a direct stream test using the AsyncStream.Continuation approach
/// - Parameters:
///   - filePrefix: Prefix for created test files
///   - fileCount: Number of files to create
///   - creationDelay: Delay between file creations in nanoseconds
/// - Returns: Array of received events matching the file prefix
private func runDirectStreamTest(
	filePrefix: String,
	fileCount: Int,
	creationDelay: UInt64
) async throws -> [FolderContentChangeEvent] {
	let tempDir = try createTempDirectory(prefix: "\(filePrefix)Test")
	defer { cleanupTempDirectory(tempDir) }

	let monitor = DirectStreamFileMonitor(url: tempDir)
	var receivedEvents: [FolderContentChangeEvent] = []

	let task = Task {
		let stream = monitor.makeStream()
		for await event in stream {
			let filename = event.filename
			if filename.hasPrefix(filePrefix) && filename.hasSuffix(".txt") && event.change.contains(.created) {
				receivedEvents.append(event)
			}
		}
	}

	// Small delay for monitor to start
	try await Task.sleep(nanoseconds: 100_000_000)  // 0.1s

	// Create test files
	let fileConfig = FileCreationConfig(
		prefix: filePrefix,
		count: fileCount,
		delay: creationDelay,
		atomicWrite: false
	)
	try await createTestFiles(in: tempDir, config: fileConfig)

	// Wait for events
	try await Task.sleep(nanoseconds: 2_000_000_000)  // 2s

	task.cancel()

	return receivedEvents
}

/// Check if event filenames are in chronological order
private func areEventsChronological(_ events: [FolderContentChangeEvent]) -> Bool {
	let filenames = events.map { $0.filename }
	return areFilenamesChronological(filenames)
}

// MARK: - MulticastAsyncStream Implementation

/// A multicast AsyncStream implementation that preserves subscriber order using OrderedDictionary.
/// This provides better ordering guarantees than Dictionary-based approaches by maintaining
/// the registration order of continuations. Uses Swift 6 Mutex for thread-safe synchronization.
public final class MulticastAsyncStream<T>: Sendable {
	private let continuations: Mutex<OrderedDictionary<UUID, AsyncStream<T>.Continuation>>

	public init() {
		self.continuations = Mutex(OrderedDictionary<UUID, AsyncStream<T>.Continuation>())

	}

	public var stream: AsyncStream<T> {
		AsyncStream { continuation in
			let id = UUID()
			continuations.withLock { dict in
				dict[id] = continuation
			}

			continuation.onTermination = { [weak self] _ in
				guard let self = self else { return }
				self.continuations.withLock { dict in
					_ = dict.removeValue(forKey: id)
				}
			}
		}
	}

	public func send(_ value: T) where T: Sendable {
		let currentContinuations = continuations.withLock { dict in
			Array(dict.values)
		}

		for c in currentContinuations {
			c.yield(value)
		}
	}
}

// MARK: - Direct Stream File Monitor Implementation

/// Simple file system monitor using direct AsyncStream.Continuation approach.
/// This bypasses actors and Task scheduling to test if we can achieve better ordering.
final class DirectStreamFileMonitor {
	private let paths: [String]
	private let latency: CFTimeInterval
	private let sinceWhen: FSEventStreamEventId
	private let multicastStream = MulticastAsyncStream<FolderContentChangeEvent>()
	private var eventStream: DirectFileSystemEventStream?

	init(
		url: URL,
		sinceWhen: FSEventStreamEventId = FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
		latency: CFTimeInterval = 0.05
	) {
		self.paths = [url.path]
		self.sinceWhen = sinceWhen
		self.latency = latency
	}

	func makeStream() -> AsyncStream<FolderContentChangeEvent> {
		// Start monitoring on first stream creation
		if eventStream == nil {
			do {
				eventStream = try DirectFileSystemEventStream(
					paths: paths,
					sinceWhen: sinceWhen,
					latency: latency,
					multicastStream: multicastStream
				)
			} catch {
				print("Failed to create DirectFileSystemEventStream: \(error)")
			}
		}

		return multicastStream.stream
	}
}

// MARK: - Direct File System Event Stream

/// Simplified RAII wrapper for FSEventStream that uses AsyncStream.Continuation directly.
final class DirectFileSystemEventStream {
	private let streamRef: FSEventStreamRef
	private let queue: DispatchQueue
	private let multicastStream: MulticastAsyncStream<FolderContentChangeEvent>

	init(
		paths: [String],
		sinceWhen: FSEventStreamEventId,
		latency: CFTimeInterval,
		multicastStream: MulticastAsyncStream<FolderContentChangeEvent>
	) throws {
		self.queue = DispatchQueue(label: "DirectFileSystemEventStream", qos: .userInteractive)
		self.multicastStream = multicastStream

		// Create the callback context - we'll pass the MulticastAsyncStream as the context
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
			throw DirectFileSystemEventStreamError.creationFailed
		}

		self.streamRef = stream

		// Configure the stream to use our queue and start monitoring
		FSEventStreamSetDispatchQueue(streamRef, queue)

		guard FSEventStreamStart(streamRef) else {
			FSEventStreamRelease(streamRef)
			throw DirectFileSystemEventStreamError.startFailed
		}
	}

	deinit {
		FSEventStreamStop(streamRef)
		FSEventStreamInvalidate(streamRef)
		FSEventStreamRelease(streamRef)
	}
}

// MARK: - FSEventStream Callback

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

// MARK: - Error Types

enum DirectFileSystemEventStreamError: Error {
	case creationFailed
	case startFailed
}
