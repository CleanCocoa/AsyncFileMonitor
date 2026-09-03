import Foundation
import Testing

@testable import AsyncFileMonitor

@Suite("Batched delivery")
struct BatchedStreamTests {

	private static func makeTempDir() throws -> URL {
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		return dir
	}

	private static func collect(
		from stream: AsyncStream<[FolderContentChangeEvent]>,
		until filename: String
	) -> Task<[[FolderContentChangeEvent]], Never> {
		Task {
			var batches: [[FolderContentChangeEvent]] = []
			for await batch in stream {
				batches.append(batch)
				if batch.contains(where: { $0.filename == filename }) { break }
			}
			return batches
		}
	}

	@Test func `batched stream delivers non-empty batches naming the changed file`() async throws {
		let tempDir = try Self.makeTempDir()
		defer { try? FileManager.default.removeItem(at: tempDir) }

		let stream = FolderContentMonitor.makeBatchedStream(url: tempDir, latency: 0.1)
		let task = Self.collect(from: stream, until: "batched.txt")

		try await Task.sleep(for: .milliseconds(200))
		try "content".write(
			to: tempDir.appendingPathComponent("batched.txt"),
			atomically: true,
			encoding: .utf8
		)

		try await Task.sleep(for: .milliseconds(1500))
		task.cancel()
		let batches = await task.value

		#expect(!batches.isEmpty)
		#expect(batches.allSatisfy { !$0.isEmpty }, "FSEvents never invokes its callback with zero events")
		#expect(batches.contains { batch in batch.contains { $0.filename == "batched.txt" } })
	}

	/// An atomic save writes a temporary file and renames it, so its events name several paths.
	/// Batching exists to keep that grouping observable.
	@Test func `an atomic save can arrive as one batch naming several paths`() async throws {
		let tempDir = try Self.makeTempDir()
		defer { try? FileManager.default.removeItem(at: tempDir) }

		let stream = FolderContentMonitor.makeBatchedStream(url: tempDir, latency: 0.3)
		let task = Self.collect(from: stream, until: "atomic.txt")

		try await Task.sleep(for: .milliseconds(200))
		try "content".write(
			to: tempDir.appendingPathComponent("atomic.txt"),
			atomically: true,
			encoding: .utf8
		)

		try await Task.sleep(for: .milliseconds(2000))
		task.cancel()
		let batches = await task.value

		#expect(batches.flatMap(\.self).contains { $0.filename == "atomic.txt" })
		#expect(
			batches.contains { $0.count > 1 },
			"a coalesced atomic save should surface as a batch of several events, got \(batches.map(\.count))"
		)
	}

	@Test func `batched stream releases its FSEventStream when dropped`() async throws {
		let tempDir = try Self.makeTempDir()
		defer { try? FileManager.default.removeItem(at: tempDir) }

		let baseline = FileSystemEventStream.liveCount.load(ordering: .relaxed)
		do {
			_ = FolderContentMonitor.makeBatchedStream(url: tempDir)
		}

		var deadline = 50
		while FileSystemEventStream.liveCount.load(ordering: .relaxed) > baseline && deadline > 0 {
			try await Task.sleep(for: .milliseconds(100))
			deadline -= 1
		}

		#expect(FileSystemEventStream.liveCount.load(ordering: .relaxed) <= baseline)
	}
}
