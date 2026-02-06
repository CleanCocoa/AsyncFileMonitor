import Foundation
import Testing

@testable import AsyncFileMonitor

@Suite("FolderContentMonitor")
struct FolderContentMonitorTests {

	private static func makeTempDir() throws -> URL {
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		return dir
	}

	@Test
	func `concurrent makeStream calls do not crash`() async throws {
		let tempDir = try Self.makeTempDir()
		defer { try? FileManager.default.removeItem(at: tempDir) }

		let monitor = FolderContentMonitor(url: tempDir)

		var tasks: [Task<Void, Never>] = []
		for _ in 0..<100 {
			tasks.append(Task { for await _ in monitor.makeStream() {} })
		}

		try await Task.sleep(for: .milliseconds(100))

		for task in tasks {
			task.cancel()
		}
		for task in tasks {
			await task.value
		}
	}

	@Test
	func `static makeStream(url:) delivers events`() async throws {
		let tempDir = try Self.makeTempDir()
		defer { try? FileManager.default.removeItem(at: tempDir) }

		let stream = FolderContentMonitor.makeStream(url: tempDir)

		let task = Task { () -> FolderContentChangeEvent? in
			for await event in stream {
				return event
			}
			return nil
		}

		try await Task.sleep(for: .milliseconds(200))

		try "test".write(
			to: tempDir.appendingPathComponent("test.txt"),
			atomically: true,
			encoding: .utf8
		)

		let event = await task.value
		#expect(event != nil)
	}

	@Test
	func `static makeStream(paths:) delivers events`() async throws {
		let tempDir = try Self.makeTempDir()
		defer { try? FileManager.default.removeItem(at: tempDir) }

		let stream = FolderContentMonitor.makeStream(paths: [tempDir.path])

		let task = Task { () -> FolderContentChangeEvent? in
			for await event in stream {
				return event
			}
			return nil
		}

		try await Task.sleep(for: .milliseconds(200))

		try "test".write(
			to: tempDir.appendingPathComponent("test.txt"),
			atomically: true,
			encoding: .utf8
		)

		let event = await task.value
		#expect(event != nil)
	}

	@Test
	func `static makeStream stops when task is cancelled`() async throws {
		let tempDir = try Self.makeTempDir()
		defer { try? FileManager.default.removeItem(at: tempDir) }

		let task = Task<Void, Never> {
			let stream = FolderContentMonitor.makeStream(url: tempDir)
			for await _ in stream {}
		}

		try await Task.sleep(for: .milliseconds(200))
		task.cancel()
		await task.value
	}

	@Test
	func `static makeStream can be dropped without starting iteration`() async throws {
		let tempDir = try Self.makeTempDir()
		defer { try? FileManager.default.removeItem(at: tempDir) }

		do {
			_ = FolderContentMonitor.makeStream(url: tempDir)
		}

		try await Task.sleep(for: .milliseconds(200))
	}
}
