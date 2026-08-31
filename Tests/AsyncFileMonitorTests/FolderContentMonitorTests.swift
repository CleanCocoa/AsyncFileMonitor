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

	@Test func `concurrent makeStream calls do not crash`() async throws {
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

	@Test func `static makeStream(url:) delivers events`() async throws {
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

	@Test func `static makeStream(paths:) delivers events`() async throws {
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

	@Test func `static makeStream stops when task is cancelled`() async throws {
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

	@Test func `static makeStream can be dropped without starting iteration`() async throws {
		let tempDir = try Self.makeTempDir()
		defer { try? FileManager.default.removeItem(at: tempDir) }

		do {
			_ = FolderContentMonitor.makeStream(url: tempDir)
		}

		try await Task.sleep(for: .milliseconds(200))
	}

	@Test func `independent monitors on the same path all receive events without interference`() async throws {
		let tempDir = try Self.makeTempDir()
		defer { try? FileManager.default.removeItem(at: tempDir) }

		let fileCount = 5
		// Atomic writes emit events for `<name>.sb-xxxx` temp files too. Match the final
		// names exactly so those intermediates cannot stand in for the files under test.
		let expectedFilenames = Set((0..<fileCount).map { "independent_\($0).txt" })

		let monitor1 = FolderContentMonitor(url: tempDir, latency: 0.1)
		let monitor2 = FolderContentMonitor(url: tempDir, latency: 0.1)
		let monitor3 = FolderContentMonitor(url: tempDir, latency: 0.1)

		let stream1 = monitor1.makeStream()
		let stream2 = monitor2.makeStream()
		let stream3 = monitor3.makeStream()

		func collectCreationEvents(
			from stream: AsyncStream<FolderContentChangeEvent>
		) -> Task<Set<String>, Never> {
			Task {
				var collected: Set<String> = []
				for await event in stream {
					guard expectedFilenames.contains(event.filename),
						event.change.contains(.created) || event.change.contains(.renamed)
					else { continue }
					collected.insert(event.filename)
					if collected == expectedFilenames { break }
				}
				return collected
			}
		}

		let task1 = collectCreationEvents(from: stream1)
		let task2 = collectCreationEvents(from: stream2)
		let task3 = collectCreationEvents(from: stream3)

		try await Task.sleep(for: .milliseconds(300))

		for i in 0..<fileCount {
			try "content \(i)".write(
				to: tempDir.appendingPathComponent("independent_\(i).txt"),
				atomically: true,
				encoding: .utf8
			)
		}

		// Bound the wait: a monitor that never sees its files must fail, not hang.
		try await Task.sleep(for: .milliseconds(1500))
		task1.cancel()
		task2.cancel()
		task3.cancel()

		let filenames1 = await task1.value
		let filenames2 = await task2.value
		let filenames3 = await task3.value

		for (label, filenames) in [("monitor1", filenames1), ("monitor2", filenames2), ("monitor3", filenames3)] {
			#expect(filenames == expectedFilenames, "\(label) missing \(expectedFilenames.subtracting(filenames))")
		}
	}

	@Test func `rapidly creating and destroying monitors during continuous file writes does not crash`() async throws {
		let tempDir = try Self.makeTempDir()
		defer { try? FileManager.default.removeItem(at: tempDir) }

		let writerTask = Task.detached {
			var counter = 0
			while !Task.isCancelled {
				try? "payload \(counter)".write(
					to: tempDir.appendingPathComponent("churn_\(counter % 5).txt"),
					atomically: false,
					encoding: .utf8
				)
				counter += 1
				try? await Task.sleep(for: .milliseconds(1))
			}
		}

		for _ in 0..<500 {
			let monitor = FolderContentMonitor(url: tempDir, latency: 0)
			let stream = monitor.makeStream()
			let task = Task { for await _ in stream {} }
			try await Task.sleep(for: .milliseconds(5))
			task.cancel()
		}

		writerTask.cancel()

		try await Task.sleep(for: .milliseconds(200))
	}
}
