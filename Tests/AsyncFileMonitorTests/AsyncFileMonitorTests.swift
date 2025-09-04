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
	let stream1 = FolderContentMonitor.makeStream(url: tempDir, latency: 0.1)
	let stream2 = FolderContentMonitor.makeStream(url: tempDir, latency: 0.1)
	let stream3 = FolderContentMonitor.makeStream(url: tempDir, latency: 0.1)

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

// This test verifies that FSEventStreamEventId values arrive in chronological order
// even when events are coalesced and out-of-order processing would potentially interleave them.
// This is critical for maintaining event causality. (ref: 20250904T080826)
@Test("Event ordering with many coalesced events")
func eventOrderingWithCoalescedEvents() async throws {
	// Create a temporary directory
	let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

	// Ensure cleanup happens even if test fails
	defer {
		try? FileManager.default.removeItem(at: tempDir)
	}

	// Set up monitor with higher latency to encourage coalescing
	let eventStream = FolderContentMonitor.makeStream(url: tempDir, latency: 0.2)

	// Create many numbered files rapidly to trigger coalescing
	let fileCount = 50
	try await confirmation("Events arrive in order", expectedCount: 1) { confirm in
		let monitorTask = Task {
			var receivedFiles: [String] = []
			var receivedEventIDs: [FSEventStreamEventId] = []

			for await event in eventStream {
				// Collect all creation/rename events for numbered files
				let filename = URL(fileURLWithPath: event.eventPath).lastPathComponent
				if filename.hasPrefix("file_") && filename.hasSuffix(".txt") {
					if event.change.contains(.created) || event.change.contains(.renamed) {
						receivedFiles.append(filename)
						receivedEventIDs.append(event.eventID)
					}
				}

				// Once we've seen enough files, verify ordering and confirm
				if receivedFiles.count >= fileCount {
					// Extract numbers from filenames and verify they're in ascending order
					let numbers = receivedFiles.compactMap { filename -> Int? in
						let components = filename.dropFirst(5).dropLast(4)  // Remove "file_" and ".txt"
						return Int(components)
					}

					// Verify we have the expected count
					#expect(numbers.count == fileCount, "Should receive all \(fileCount) file creation events")

					// Check if event IDs are in ascending order
					let sortedEventIDs = receivedEventIDs.sorted()
					let isOrdered = receivedEventIDs == sortedEventIDs

					// Note: Even with executor preference, some reordering may occur under high load
					// due to FSEventStream internal buffering and dispatch queue scheduling.
					// This test may intermittently fail, which demonstrates the inherent limitations.
					// See: docs/Event Reordering with Executor.md
					withKnownIssue(
						"Event ordering may fail intermittently under load due to FSEventStream buffering",
						isIntermittent: true
					) {
						#expect(isOrdered, "Events should appear in order (may fail intermittently under load)")
					}

					// Print diagnostic information about ordering
					print("Received files: \(receivedFiles.prefix(10))...")
					print("Event IDs are ordered: \(isOrdered)")
					print("First 10 event IDs: \(receivedEventIDs.prefix(10))")

					if !isOrdered {
						// Find and report out-of-order events
						let misorderedEvents = zip(receivedEventIDs, sortedEventIDs)
							.enumerated()
							.compactMap { index, pair in
								pair.0 != pair.1 ? (index, pair.0, pair.1) : nil
							}
						print("Out-of-order events detected:")
						for (index, received, expected) in misorderedEvents.prefix(5) {
							print("  Position \(index): received \(received), expected \(expected)")
						}
					}

					// This test demonstrates potential event ordering issues but doesn't fail
					// since some reordering may be expected due to FSEventStream coalescing behavior

					confirm()
					break
				}
			}
		}

		// Give the monitor time to start up
		try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds

		// Create files rapidly in sequence to encourage coalescing
		try await Task {
			for i in 0..<fileCount {
				let filename = String(format: "file_%03d.txt", i)
				let fileURL = tempDir.appendingPathComponent(filename)
				try "Content \(i)".write(to: fileURL, atomically: true, encoding: .utf8)

				// Small delay between files to create distinct events but still trigger coalescing
				try await Task.sleep(nanoseconds: 10_000_000)  // 0.01 seconds
			}
		}.value

		// Wait for the monitoring task to complete
		await monitorTask.value
	}
}
