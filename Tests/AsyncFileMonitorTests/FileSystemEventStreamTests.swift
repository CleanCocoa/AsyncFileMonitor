import Foundation
import Testing

@testable import AsyncFileMonitor

@Suite("FileSystemEventStream")
struct FileSystemEventStreamTests {

	private static func makeTempDir() throws -> URL {
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		return dir
	}

	@Test func `events are correctly delivered through callback`() async throws {
		let tempDir = try Self.makeTempDir()
		defer { try? FileManager.default.removeItem(at: tempDir) }

		try await confirmation(expectedCount: 1) { confirmation in
			let stream = try FileSystemEventStream.make(
				paths: [tempDir.path],
				sinceWhen: FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
				latency: 0.1
			) { batch in
				for event in batch where event.eventPath.hasSuffix("test.txt") {
					confirmation()
				}
			}

			try await Task.sleep(for: .milliseconds(200))

			try "content".write(
				to: tempDir.appendingPathComponent("test.txt"),
				atomically: true,
				encoding: .utf8
			)

			try await Task.sleep(for: .milliseconds(500))
			withExtendedLifetime(stream) {}
		}
	}

	@Test func `rapidly creating and destroying streams with concurrent events does not crash`() async throws {
		let tempDir = try Self.makeTempDir()
		defer { try? FileManager.default.removeItem(at: tempDir) }

		for iteration in 0..<50 {
			let stream = try FileSystemEventStream.make(
				paths: [tempDir.path],
				sinceWhen: FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
				latency: 0.01
			) { batch in
				_ = batch
			}

			try await Task.sleep(for: .milliseconds(10))

			try "iteration \(iteration)".write(
				to: tempDir.appendingPathComponent("file_\(iteration).txt"),
				atomically: true,
				encoding: .utf8
			)

			try await Task.sleep(for: .milliseconds(20))

			withExtendedLifetime(stream) {}
		}

		try await Task.sleep(for: .milliseconds(500))
	}

	@Test func `destroying stream while events are in flight does not crash`() async throws {
		let tempDir = try Self.makeTempDir()
		defer { try? FileManager.default.removeItem(at: tempDir) }

		for iteration in 0..<100 {
			_ = try FileSystemEventStream.make(
				paths: [tempDir.path],
				sinceWhen: FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
				latency: 0.01
			) { batch in
				_ = batch
			}

			try "data".write(
				to: tempDir.appendingPathComponent("file_\(iteration).txt"),
				atomically: true,
				encoding: .utf8
			)
		}

		try await Task.sleep(for: .milliseconds(200))
	}

	@Test func `stream correctly processes multiple events`() async throws {
		let tempDir = try Self.makeTempDir()
		defer { try? FileManager.default.removeItem(at: tempDir) }

		try await confirmation(expectedCount: 3) { confirmation in
			let fileNames = ["file1.txt", "file2.txt", "file3.txt"]

			let stream = try FileSystemEventStream.make(
				paths: [tempDir.path],
				sinceWhen: FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
				latency: 0.1
			) { batch in
				for event in batch {
					let filename = URL(fileURLWithPath: event.eventPath).lastPathComponent
					if fileNames.contains(filename) {
						confirmation()
					}
				}
			}

			try await Task.sleep(for: .milliseconds(200))

			for fileName in fileNames {
				try "content".write(
					to: tempDir.appendingPathComponent(fileName),
					atomically: true,
					encoding: .utf8
				)
			}

			try await Task.sleep(for: .milliseconds(500))
			withExtendedLifetime(stream) {}
		}
	}
}
