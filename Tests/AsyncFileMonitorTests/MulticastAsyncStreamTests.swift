import Foundation
import Testing

@testable import AsyncFileMonitor

@Suite("MulticastAsyncStream")
struct MulticastAsyncStreamTests {

	@Test
	func `currentStreamCount reflects number of live streams`() async throws {
		let multicast = MulticastAsyncStream<Int>()

		#expect(multicast.currentStreamCount == 0)

		let task1 = Task { for await _ in multicast.makeStream() {} }
		let task2 = Task { for await _ in multicast.makeStream() {} }
		let task3 = Task { for await _ in multicast.makeStream() {} }

		try await Task.sleep(for: .milliseconds(50))
		#expect(multicast.currentStreamCount == 3)

		task1.cancel()
		task2.cancel()
		try await Task.sleep(for: .milliseconds(50))
		#expect(multicast.currentStreamCount == 1)

		task3.cancel()
		try await Task.sleep(for: .milliseconds(50))
		#expect(multicast.currentStreamCount == 0)
	}

	@Test
	func `single stream lifecycle produces correct events`() async throws {
		let multicast = MulticastAsyncStream<Int>()
		let lifecycleStream = multicast.makeLifecycleStream()

		let lifecycleTask = Task {
			var events: [StreamLifecycleEvent] = []
			for await event in lifecycleStream {
				events.append(event)
				if event == .lastStreamRemoved { break }
			}
			return events
		}

		try await Task.sleep(for: .milliseconds(50))

		let streamTask = Task { for await _ in multicast.makeStream() {} }
		try await Task.sleep(for: .milliseconds(50))
		streamTask.cancel()

		let events = await lifecycleTask.value
		#expect(events == [.firstStreamAdded, .lastStreamRemoved])
	}

	@Test
	func `multiple streams only trigger lifecycle events once`() async throws {
		let multicast = MulticastAsyncStream<Int>()
		let lifecycleStream = multicast.makeLifecycleStream()

		let lifecycleTask = Task {
			var events: [StreamLifecycleEvent] = []
			for await event in lifecycleStream {
				events.append(event)
				if event == .lastStreamRemoved { break }
			}
			return events
		}

		try await Task.sleep(for: .milliseconds(50))

		let task1 = Task { for await _ in multicast.makeStream() {} }
		let task2 = Task { for await _ in multicast.makeStream() {} }
		let task3 = Task { for await _ in multicast.makeStream() {} }

		try await Task.sleep(for: .milliseconds(50))

		task1.cancel()
		task2.cancel()
		task3.cancel()

		let events = await lifecycleTask.value
		#expect(events == [.firstStreamAdded, .lastStreamRemoved])
	}

	@Test
	func `send broadcasts to all active streams`() async throws {
		let multicast = MulticastAsyncStream<Int>()

		let task1 = Task {
			var values: [Int] = []
			let stream = multicast.makeStream()
			for await value in stream {
				values.append(value)
				if value == 3 { break }
			}
			return values
		}

		let task2 = Task {
			var values: [Int] = []
			let stream = multicast.makeStream()
			for await value in stream {
				values.append(value)
				if value == 3 { break }
			}
			return values
		}

		try await Task.sleep(for: .milliseconds(100))

		multicast.send(1)
		multicast.send(2)
		multicast.send(3)

		let values1 = await task1.value
		let values2 = await task2.value

		#expect(values1 == [1, 2, 3])
		#expect(values2 == [1, 2, 3])
	}

	@Test
	func `lifecycle events arrive in correct order under concurrent stress`() async throws {
		let multicast = MulticastAsyncStream<Int>()
		let lifecycleStream = multicast.makeLifecycleStream()

		let lifecycleTask = Task {
			var events: [StreamLifecycleEvent] = []
			for await event in lifecycleStream {
				events.append(event)
				if event == .lastStreamRemoved && events.count >= 2 {
					break
				}
			}
			return events
		}

		try await Task.sleep(for: .milliseconds(50))

		await withTaskGroup(of: Void.self) { group in
			for _ in 0..<100 {
				group.addTask {
					let innerTask = Task { for await _ in multicast.makeStream() {} }
					try? await Task.sleep(for: .milliseconds(1))
					innerTask.cancel()
					await innerTask.value
				}
			}
		}

		let events = await lifecycleTask.value

		#expect(events.count >= 2)
		#expect(events.first == .firstStreamAdded)
		#expect(events.last == .lastStreamRemoved)

		for i in 0..<(events.count - 1) {
			if events[i] == .lastStreamRemoved {
				#expect(events[i + 1] == .firstStreamAdded)
			}
		}
	}
}
