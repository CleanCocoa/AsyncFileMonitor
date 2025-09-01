//
//  AsyncFileMonitorTests.swift
//  AsyncFileMonitorTests
//
//  Created by Christian Tietze on 08/11/16.
//  Copyright © 2025 Christian Tietze (AsyncFileMonitor test suite)
//

import Foundation
import Testing

@testable import AsyncFileMonitor

@Test("File monitoring integration")
func fileMonitoringIntegration() async throws {
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
	let eventStream = FolderContentMonitor.monitor(url: tempDir, latency: 0.1)

	// Monitor events and wait for the expected ones
	let eventsReceived = await withCheckedContinuation { continuation in
		var receivedEvents: [FolderContentChangeEvent] = []

		let monitorTask = Task {
			for await event in eventStream {
				receivedEvents.append(event)

				// Check if we've received the specific events we're looking for:
				// - b.txt with removed flag
				// - d.txt with either created or renamed flag (atomic saves use rename)
				let bDeleted = receivedEvents.contains {
					$0.matches(filename: "b.txt", change: .removed)
				}
				let dCreated = receivedEvents.contains { event in
					event.matches(filename: "d.txt", change: .created)
						|| event.matches(filename: "d.txt", change: .renamed)
				}

				if bDeleted && dCreated {
					continuation.resume(returning: true)
					break
				}
			}
		}

		// Set up timeout
		let timeoutTask = Task {
			try await Task.sleep(nanoseconds: 5_000_000_000)  // 5 seconds
			continuation.resume(returning: false)
			monitorTask.cancel()
		}

		// Give the monitor time to start up, then make the file changes
		Task {
			try await Task.sleep(nanoseconds: 200_000_000)  // 0.2 seconds

			// Delete file b and create file d
			try FileManager.default.removeItem(at: fileB)
			try "File D".write(to: fileD, atomically: true, encoding: .utf8)
		}

		// Clean up when events are received
		Task {
			_ = await monitorTask.result
			timeoutTask.cancel()
		}
	}

	#expect(eventsReceived, "Should receive expected file system events within timeout")
}
