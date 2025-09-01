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

	func testFileMonitoringIntegration() async throws {
		// Create a temporary directory
		let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
		
		// Ensure cleanup happens even if test fails
		defer {
			try? FileManager.default.removeItem(at: tempDir)
		}
		
		// Create initial files a, b, c
		let fileA = tempDir.appendingPathComponent("a.txt")
		let fileB = tempDir.appendingPathComponent("b.txt")
		let fileC = tempDir.appendingPathComponent("c.txt")
		let fileD = tempDir.appendingPathComponent("d.txt")
		
		try "File A".write(to: fileA, atomically: true, encoding: .utf8)
		try "File B".write(to: fileB, atomically: true, encoding: .utf8)
		try "File C".write(to: fileC, atomically: true, encoding: .utf8)
		
		// Set up monitor with a small latency to coalesce rapid changes
		let monitor = FolderContentMonitor(url: tempDir, latency: 0.1)
		let eventStream = monitor.makeAsyncStream()
		
		// Collect events in the background
		var receivedEvents: [FolderContentChangeEvent] = []
		let expectation = XCTestExpectation(description: "Receive file system events")
		
		let monitorTask = Task {
			for await event in eventStream {
				receivedEvents.append(event)
				print("Event received: \(event.filename) - \(event.change)")
				
				// Check if we've received events for both b deletion and d creation
				let filenames = Set(receivedEvents.map { $0.filename })
				if filenames.contains("b.txt") && filenames.contains("d.txt") {
					expectation.fulfill()
					break
				}
			}
		}
		
		// Give the monitor time to start up
		try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
		
		// Delete file b and create file d
		try FileManager.default.removeItem(at: fileB)
		try "File D".write(to: fileD, atomically: true, encoding: .utf8)
		
		// Wait for events with timeout
		let result = await XCTWaiter.fulfillment(of: [expectation], timeout: 5.0)
		
		// Cancel the monitoring task
		monitorTask.cancel()
		
		// Verify we received the expected events
		XCTAssertEqual(result, .completed, "Should receive file system events within timeout")
		
		// Check that we got events for both files
		let eventFilenames = Set(receivedEvents.map { $0.filename })
		XCTAssertTrue(eventFilenames.contains("b.txt"), "Should receive event for deleted file b.txt")
		XCTAssertTrue(eventFilenames.contains("d.txt"), "Should receive event for created file d.txt")
		
		// Verify we got some meaningful events for each file
		let bEvents = receivedEvents.filter { $0.filename == "b.txt" }
		let dEvents = receivedEvents.filter { $0.filename == "d.txt" }
		
		XCTAssertFalse(bEvents.isEmpty, "Should have at least one event for b.txt")
		XCTAssertFalse(dEvents.isEmpty, "Should have at least one event for d.txt")
		
		// FSEvents may report various flags depending on how files are created/deleted
		// Just verify we got events rather than checking specific flags
		print("b.txt events: \(bEvents.map { $0.change })")
		print("d.txt events: \(dEvents.map { $0.change })")
	}
}
