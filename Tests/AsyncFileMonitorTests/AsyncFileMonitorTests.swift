//
//  AsyncFileMonitorTests.swift
//  AsyncFileMonitorTests
//
//  Created by Christian Tietze on 08/11/16.
//  Copyright © 2025 Christian Tietze (AsyncFileMonitor test suite)
//

import Foundation
import XCTest

@testable import AsyncFileMonitor

final class AsyncFileMonitorTests: XCTestCase {

	func testFolderContentMonitorInitialization() {
		let url = URL(fileURLWithPath: "/tmp")
		let monitor = FolderContentMonitor(url: url)

		XCTAssertEqual(monitor.pathsToWatch, ["/tmp"])
		XCTAssertFalse(monitor.hasStarted)
		XCTAssertEqual(monitor.latency, 0)
	}

	func testFolderContentMonitorWithMultiplePaths() {
		let paths = ["/tmp", "/var"]
		let monitor = FolderContentMonitor(pathsToWatch: paths)

		XCTAssertEqual(monitor.pathsToWatch, paths)
		XCTAssertFalse(monitor.hasStarted)
	}

	func testFolderContentMonitorWithCustomLatency() {
		let url = URL(fileURLWithPath: "/tmp")
		let latency: CFTimeInterval = 0.5
		let monitor = FolderContentMonitor(url: url, latency: latency)

		XCTAssertEqual(monitor.latency, latency)
	}

	func testFolderContentChangeEventCreation() {
		let event = FolderContentChangeEvent(
			eventId: 12345,
			eventPath: "/tmp/test.txt",
			change: .created
		)

		XCTAssertEqual(event.eventId, 12345)
		XCTAssertEqual(event.eventPath, "/tmp/test.txt")
		XCTAssertEqual(event.filename, "test.txt")
		XCTAssertEqual(event.url, URL(fileURLWithPath: "/tmp/test.txt"))
		XCTAssertTrue(event.change.contains(.created))
	}

	func testChangeDescription() {
		let created = Change.created
		XCTAssertEqual(created.description, "created")

		let combined = Change([.created, .isFile])
		XCTAssertTrue(combined.description.contains("created"))
		XCTAssertTrue(combined.description.contains("isFile"))
	}

	func testChangeFromEventFlags() {
		let flags = FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated)
		let change = Change(eventFlags: flags)

		XCTAssertTrue(change.contains(.created))
	}

	func testAsyncFileMonitorConvenienceMethods() {
		let url = URL(fileURLWithPath: "/tmp")
		let monitor1 = AsyncFileMonitor.monitor(url: url)

		XCTAssertEqual(monitor1.pathsToWatch, ["/tmp"])

		let paths = ["/tmp", "/var"]
		let monitor2 = AsyncFileMonitor.monitor(paths: paths)

		XCTAssertEqual(monitor2.pathsToWatch, paths)
	}

	func testEventDescription() {
		let event = FolderContentChangeEvent(
			eventId: 12345,
			eventPath: "/tmp/test.txt",
			change: .created
		)

		let description = event.description
		XCTAssertTrue(description.contains("/tmp/test.txt"))
		XCTAssertTrue(description.contains("12345"))
		XCTAssertTrue(description.contains("created"))
	}

	// NOTE: Testing actual file system monitoring requires more complex setup
	// with temporary directories and file creation, which would make tests
	// more brittle. The core functionality is tested through the public API
	// and the FSEvents integration is tested through the callback mechanism.
}
