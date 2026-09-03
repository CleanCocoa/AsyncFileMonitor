import Foundation
import Synchronization
import Testing

@testable import AsyncFileMonitor

/// Proves that dropping a stream tears down the kernel `FSEventStream`, not just the Swift wrapper.
///
/// Serialized because the assertions read a process-wide live count.
@Suite("Stream teardown", .serialized)
struct StreamTeardownTests {

	private static func makeTempDir() throws -> URL {
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		return dir
	}

	/// Teardown is asynchronous with respect to the consumer, so poll rather than sleep once.
	private static func waitForLiveCount(toReachAtMost target: Int) async -> Int {
		let deadline = ContinuousClock.now + .seconds(5)
		var live = FileSystemEventStream.liveCount.load(ordering: .relaxed)
		while live > target, ContinuousClock.now < deadline {
			try? await Task.sleep(for: .milliseconds(20))
			live = FileSystemEventStream.liveCount.load(ordering: .relaxed)
		}
		return live
	}

	// MARK: - Direct wrapper

	/// The strongest available signal, and the only race-free one: releasing the FSEventStream
	/// runs the context release callback, which frees the handler closure and anything it holds.
	@Test func `dropping FileSystemEventStream releases the event handler`() async throws {
		let tempDir = try Self.makeTempDir()
		defer { try? FileManager.default.removeItem(at: tempDir) }

		final class Sentinel: Sendable {}
		weak var weakSentinel: Sentinel?

		do {
			let sentinel = Sentinel()
			weakSentinel = sentinel
			let eventStream = try FileSystemEventStream.make(
				paths: [tempDir.path],
				sinceWhen: FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
				latency: 0,
				eventHandler: { _ in withExtendedLifetime(sentinel) {} }
			)
			#expect(weakSentinel != nil)
			_ = consume eventStream
		}

		// FSEventStreamRelease runs the context release callback on the stream's dispatch
		// queue, so the handler is freed shortly after the call rather than during it.
		let deadline = ContinuousClock.now + .seconds(5)
		while weakSentinel != nil, ContinuousClock.now < deadline {
			try await Task.sleep(for: .milliseconds(20))
		}

		#expect(weakSentinel == nil, "FSEventStream release did not free the event handler")
	}

	// MARK: - Static conveniences

	@Test func `static makeStream releases the FSEventStream when dropped without iteration`() async throws {
		let tempDir = try Self.makeTempDir()
		defer { try? FileManager.default.removeItem(at: tempDir) }

		let baseline = FileSystemEventStream.liveCount.load(ordering: .relaxed)
		do { _ = try FolderContentMonitor.makeStream(url: tempDir) }

		#expect(await Self.waitForLiveCount(toReachAtMost: baseline) <= baseline)
	}

	@Test func `static makeStream releases the FSEventStream when the consumer is cancelled`() async throws {
		let tempDir = try Self.makeTempDir()
		defer { try? FileManager.default.removeItem(at: tempDir) }

		let baseline = FileSystemEventStream.liveCount.load(ordering: .relaxed)
		do {
			let stream = try FolderContentMonitor.makeStream(url: tempDir)
			let task = Task { for await _ in stream {} }
			try await Task.sleep(for: .milliseconds(100))
			task.cancel()
			await task.value
		}

		#expect(await Self.waitForLiveCount(toReachAtMost: baseline) <= baseline)
	}

	@Test func `static makeStream releases the FSEventStream when the consumer breaks`() async throws {
		let tempDir = try Self.makeTempDir()
		defer { try? FileManager.default.removeItem(at: tempDir) }

		let baseline = FileSystemEventStream.liveCount.load(ordering: .relaxed)
		do {
			let stream = try FolderContentMonitor.makeStream(url: tempDir)
			let task = Task {
				try? "trigger".write(
					to: tempDir.appendingPathComponent("trigger.txt"),
					atomically: true,
					encoding: .utf8
				)
				for await _ in stream { break }
			}
			await task.value
		}

		#expect(await Self.waitForLiveCount(toReachAtMost: baseline) <= baseline)
	}

	/// `liveCount` is process-wide, so this belongs in the serialized suite rather than beside
	/// the other startup-failure tests.
	@Test func `a failed startup leaves no FSEventStream running`() async throws {
		let baseline = FileSystemEventStream.liveCount.load(ordering: .relaxed)

		#expect(throws: FolderContentMonitor.Error.self) {
			_ = try FolderContentMonitor.makeStream(paths: [])
		}

		#expect(await Self.waitForLiveCount(toReachAtMost: baseline) <= baseline)
	}
}
