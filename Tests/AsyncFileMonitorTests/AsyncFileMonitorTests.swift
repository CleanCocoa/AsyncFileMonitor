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
	let eventStream = FolderContentMonitor.makeStream(url: tempDir, latency: 0.1)

	// Monitor events and confirm we receive the expected ones
	try await confirmation("Receive file system events", expectedCount: 2) { confirm in
		var confirmationCount = 0

		let monitorTask = Task {
			for await event in eventStream {
				// Confirm specific events we're looking for:
				// - b.txt with removed flag
				// - d.txt with either created or renamed flag (atomic saves use rename)
				if event.matches(filename: "b.txt", change: .removed) {
					confirm(count: 1)
					confirmationCount += 1
				} else if event.matches(filename: "d.txt", change: .created)
					|| event.matches(filename: "d.txt", change: .renamed)
				{
					confirm(count: 1)
					confirmationCount += 1
				}

				// Break early once we have both confirmations
				if confirmationCount >= 2 {
					break
				}
			}
		}

		// Give the monitor time to start up, then make the file changes
		try await Task {
			try await Task.sleep(nanoseconds: 200_000_000)  // 0.2 seconds

			// Delete file b and create file d
			try FileManager.default.removeItem(at: fileB)
			try "File D".write(to: fileD, atomically: true, encoding: .utf8)
		}.value

		// Wait for the monitoring task to complete
		await monitorTask.value
	}
}

@Test("Multiple streams from single monitor")
func multipleStreamsFromSingleMonitor() async throws {
	// Create a temporary directory
	let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

	// Ensure cleanup happens even if test fails
	defer {
		try? FileManager.default.removeItem(at: tempDir)
	}

	// Create initial file
	let testFile = tempDir.appendingPathComponent("test.txt")
	try "Initial".write(to: testFile, atomically: true, encoding: .utf8)

	// Create multiple streams for the same directory
	let stream1 = AsyncFileMonitor.monitor(url: tempDir, latency: 0.1)
	let stream2 = AsyncFileMonitor.monitor(url: tempDir, latency: 0.1)
	let stream3 = AsyncFileMonitor.monitor(url: tempDir, latency: 0.1)

	// Monitor events and confirm each stream receives them
	try await confirmation("All streams receive file system events", expectedCount: 6) { confirm in
		var stream1Count = 0
		var stream2Count = 0
		var stream3Count = 0

		let task1 = Task {
			for await event in stream1 {
				if event.matches(filename: "test.txt", change: .modified)
					|| event.matches(filename: "new.txt", change: .created)
					|| event.matches(filename: "new.txt", change: .renamed)
				{
					confirm(count: 1)
					stream1Count += 1
					if stream1Count >= 2 { break }
				}
			}
		}

		let task2 = Task {
			for await event in stream2 {
				if event.matches(filename: "test.txt", change: .modified)
					|| event.matches(filename: "new.txt", change: .created)
					|| event.matches(filename: "new.txt", change: .renamed)
				{
					confirm(count: 1)
					stream2Count += 1
					if stream2Count >= 2 { break }
				}
			}
		}

		let task3 = Task {
			for await event in stream3 {
				if event.matches(filename: "test.txt", change: .modified)
					|| event.matches(filename: "new.txt", change: .created)
					|| event.matches(filename: "new.txt", change: .renamed)
				{
					confirm(count: 1)
					stream3Count += 1
					if stream3Count >= 2 { break }
				}
			}
		}

		// Give streams time to start, then make file changes
		try await Task {
			try await Task.sleep(nanoseconds: 200_000_000)  // 0.2 seconds

			// Modify existing file and create new file
			try "Modified".write(to: testFile, atomically: true, encoding: .utf8)
			let newFile = tempDir.appendingPathComponent("new.txt")
			try "New file".write(to: newFile, atomically: true, encoding: .utf8)
		}.value

		// Wait for all tasks to complete
		await task1.value
		await task2.value
		await task3.value
	}
}
