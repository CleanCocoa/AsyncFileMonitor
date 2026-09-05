import Foundation
import Testing

@testable import AsyncFileMonitor

/// Covers `Configuration.sinceWhen`, the only path that produces historical events and the
/// ``StreamCondition/historyDone`` sentinel that ends them.
@Suite("Replay from a stored event ID")
struct ReplayTests {

	private static func makeTempDir() throws -> URL {
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		return dir
	}

	@Test func `sinceWhen replays what changed while nothing watched, then signals historyDone`() async throws {
		let tempDir = try Self.makeTempDir()
		defer { try? FileManager.default.removeItem(at: tempDir) }

		// 1. Watch live, only to obtain a real event ID to resume from.
		let live = try FolderContentMonitor.makeStream(url: tempDir, configuration: .init(latency: 0.1))
		let capture = Task { () -> FSEventStreamEventId? in
			for await event in live { return event.eventID }
			return nil
		}

		try await Task.sleep(for: .milliseconds(300))
		try "one".write(
			to: tempDir.appendingPathComponent("one.txt"),
			atomically: true,
			encoding: .utf8
		)
		try await Task.sleep(for: .milliseconds(1500))
		capture.cancel()
		let resumeFrom = try #require(await capture.value, "never observed an event to resume from")

		// 2. Change the folder with nothing watching it. Replay reads FSEvents' own log, so the
		// write has to be journaled before the resuming stream is created — without this pause
		// the test fails whenever nothing else is loading the machine.
		try "two".write(
			to: tempDir.appendingPathComponent("two.txt"),
			atomically: true,
			encoding: .utf8
		)
		try await Task.sleep(for: .milliseconds(500))

		// 3. Resume. The missed change must be replayed, then the sentinel.
		let replay = try FolderContentMonitor.makeStream(
			url: tempDir,
			configuration: .init(sinceWhen: resumeFrom, latency: 0.1)
		)
		let collect = Task { () -> [FolderContentChangeEvent] in
			var collected: [FolderContentChangeEvent] = []
			for await event in replay {
				collected.append(event)
				if event.condition.contains(.historyDone) { break }
			}
			return collected
		}

		try await Task.sleep(for: .milliseconds(2500))
		collect.cancel()
		let events = await collect.value

		let sentinel = try #require(
			events.firstIndex { $0.condition.contains(.historyDone) },
			"no historyDone sentinel arrived"
		)
		let replayed = try #require(
			events.firstIndex { $0.filename == "two.txt" },
			"the change made while nothing watched was not replayed"
		)

		#expect(replayed < sentinel, "historical events must precede the sentinel that ends them")
		// The only assertion anywhere that a condition-only element survives the public stream
		// rather than being dropped as "nothing changed".
		#expect(events[sentinel].change.isEmpty, "the sentinel reports no file change")
	}
}
