#if os(Linux)
import Foundation
import Testing

@testable import AsyncFileMonitorLinux

struct LibuvFileMonitorTests {

	@Test("LibuvFileMonitor can be created")
	func testCreation() {
		let tempURL = URL(fileURLWithPath: "/tmp")
		let monitor = LibuvFileMonitor(urls: [tempURL])

		#expect(monitor != nil)
	}

	@Test("LibuvFileMonitor makeStream creates AsyncStream")
	func testMakeStream() {
		let tempURL = URL(fileURLWithPath: "/tmp")
		let stream = LibuvFileMonitor.makeStream(url: tempURL)

		#expect(stream != nil)
	}

	@Test("Change flags work correctly")
	func testChangeFlags() {
		let change = Change([.isFile, .modified])

		#expect(change.contains(.isFile))
		#expect(change.contains(.modified))
		#expect(!change.contains(.isDirectory))
	}

	@Test("FolderContentChangeEvent creation")
	func testEventCreation() {
		let change = Change([.isFile, .created])
		let event = FolderContentChangeEvent(
			eventId: 12345,
			eventPath: "/tmp/test.txt",
			eventFlags: 0x01,
			change: change
		)

		#expect(event.id == 12345)
		#expect(event.eventPath == "/tmp/test.txt")
		#expect(event.filename == "test.txt")
		#expect(event.change == change)
	}

	@Test("MulticastAsyncStream basic functionality")
	func testMulticastStream() async {
		let multicastStream = MulticastAsyncStream<Int>()

		let stream = multicastStream.makeStream()

		Task {
			multicastStream.send(42)
			multicastStream.finish()
		}

		var receivedValues: [Int] = []
		for await value in stream {
			receivedValues.append(value)
		}

		#expect(receivedValues == [42])
	}
}
#endif
