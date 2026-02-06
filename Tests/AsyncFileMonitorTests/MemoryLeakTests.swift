import Foundation
import Testing

@testable import AsyncFileMonitor

@Suite("Memory and Lifetime")
struct MemoryLeakTests {

	private static func makeTempDir() throws -> URL {
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		return dir
	}

	// MARK: - Baseline: no retain cycle without makeStream()

	@Test func `monitor deallocates when makeStream() was never called`() throws {
		let tempDir = try Self.makeTempDir()
		defer { try? FileManager.default.removeItem(at: tempDir) }

		weak var weakMonitor: FolderContentMonitor?
		do {
			let monitor = FolderContentMonitor(url: tempDir)
			weakMonitor = monitor
		}

		#expect(weakMonitor == nil)
	}

	// MARK: - Retain cycle: lifecycleTask captures self

	@Test func `monitor deallocates after stream is dropped without iteration`() async throws {
		let tempDir = try Self.makeTempDir()
		defer { try? FileManager.default.removeItem(at: tempDir) }

		weak var weakMonitor: FolderContentMonitor?
		do {
			let monitor = FolderContentMonitor(url: tempDir)
			weakMonitor = monitor
			_ = monitor.makeStream()
		}

		try await Task.sleep(for: .milliseconds(500))

		withKnownIssue("lifecycleTask captures self via start()/stop(), creating a retain cycle") {
			#expect(weakMonitor == nil)
		}
	}

	@Test func `monitor deallocates after consumer breaks from iteration`() async throws {
		let tempDir = try Self.makeTempDir()
		defer { try? FileManager.default.removeItem(at: tempDir) }

		weak var weakMonitor: FolderContentMonitor?
		do {
			let monitor = FolderContentMonitor(url: tempDir)
			weakMonitor = monitor
			let stream = monitor.makeStream()

			let task = Task {
				for await _ in stream { break }
			}

			try await Task.sleep(for: .milliseconds(200))
			try "trigger".write(
				to: tempDir.appendingPathComponent("test.txt"),
				atomically: true,
				encoding: .utf8
			)
			await task.value
		}

		try await Task.sleep(for: .milliseconds(500))

		withKnownIssue("lifecycleTask holds self even after all consumers stopped") {
			#expect(weakMonitor == nil)
		}
	}

	@Test func `monitor deallocates after multiple streams created and dropped`() async throws {
		let tempDir = try Self.makeTempDir()
		defer { try? FileManager.default.removeItem(at: tempDir) }

		weak var weakMonitor: FolderContentMonitor?
		do {
			let monitor = FolderContentMonitor(url: tempDir)
			weakMonitor = monitor
			let s1 = monitor.makeStream()
			let s2 = monitor.makeStream()
			let s3 = monitor.makeStream()
			withExtendedLifetime((s1, s2, s3)) {}
		}

		try await Task.sleep(for: .milliseconds(500))

		withKnownIssue("lifecycleTask retains monitor permanently") {
			#expect(weakMonitor == nil)
		}
	}

	// MARK: - MulticastAsyncStream baseline

	@Test func `MulticastAsyncStream deallocates after all streams end`() async throws {
		weak var weakMulticast: MulticastAsyncStream<Int>?

		do {
			let multicast = MulticastAsyncStream<Int>()
			weakMulticast = multicast
			let stream = multicast.makeStream()
			withExtendedLifetime(stream) {}
		}

		try await Task.sleep(for: .milliseconds(200))

		#expect(weakMulticast == nil)
	}

	@Test func `MulticastAsyncStream cleans up continuation when stream is dropped`() async throws {
		let multicast = MulticastAsyncStream<Int>()

		do {
			let stream = multicast.makeStream()
			#expect(multicast.currentStreamCount == 1)
			withExtendedLifetime(stream) {}
		}

		try await Task.sleep(for: .milliseconds(200))

		#expect(multicast.currentStreamCount == 0)
	}
}
