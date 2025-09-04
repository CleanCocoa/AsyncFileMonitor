//
// EventCollector.swift
// TestHelpers
//
// Protocol-based event collection system for file system monitoring tests.
// Supports both thread-safe and unsafe implementations for educational purposes.
//
// Reference: 20250904T105810
//

import Foundation

/// Protocol for collecting FSEventStream events during tests
public protocol FSEventCollector: AnyObject {
	/// Record a file system event
	func recordEvent(eventID: FSEventStreamEventId, path: String)

	/// Analyze collected events and return results
	func analyzeEvents() -> FSEventTestResult
}

/// Result of analyzing collected file system events
public struct FSEventTestResult {
	public let totalEvents: Int
	public let isChronological: Bool
	public let eventIDRange: (min: FSEventStreamEventId, max: FSEventStreamEventId)?
	public let timingStats: FSEventTimingStats?
	public let possiblyCorrupted: Bool  // For unsafe implementations

	public init(
		totalEvents: Int,
		isChronological: Bool,
		eventIDRange: (min: FSEventStreamEventId, max: FSEventStreamEventId)?,
		timingStats: FSEventTimingStats?,
		possiblyCorrupted: Bool = false
	) {
		self.totalEvents = totalEvents
		self.isChronological = isChronological
		self.eventIDRange = eventIDRange
		self.timingStats = timingStats
		self.possiblyCorrupted = possiblyCorrupted
	}
}

/// Timing statistics for collected events
public struct FSEventTimingStats {
	public let averageInterval: TimeInterval
	public let minInterval: TimeInterval
	public let maxInterval: TimeInterval

	public init(averageInterval: TimeInterval, minInterval: TimeInterval, maxInterval: TimeInterval) {
		self.averageInterval = averageInterval
		self.minInterval = minInterval
		self.maxInterval = maxInterval
	}
}

// MARK: - Thread-Safe Implementation

/// Thread-safe event collector using proper locking
public final class ThreadSafeEventCollector: FSEventCollector {
	private let lock = NSLock()
	private var events: [(eventID: FSEventStreamEventId, path: String, receivedAt: Date)] = []

	public init() {}

	public func recordEvent(eventID: FSEventStreamEventId, path: String) {
		lock.lock()
		defer { lock.unlock() }
		events.append((eventID: eventID, path: path, receivedAt: Date()))
	}

	public func analyzeEvents() -> FSEventTestResult {
		lock.lock()
		defer { lock.unlock() }

		let eventIDs = events.map { $0.eventID }
		let sortedIDs = eventIDs.sorted()
		let isChronological = eventIDs == sortedIDs

		var timingStats: FSEventTimingStats?
		if events.count > 1 {
			let intervals = zip(events, events.dropFirst()).map { current, next in
				next.receivedAt.timeIntervalSince(current.receivedAt)
			}
			timingStats = FSEventTimingStats(
				averageInterval: intervals.reduce(0, +) / Double(intervals.count),
				minInterval: intervals.min() ?? 0,
				maxInterval: intervals.max() ?? 0
			)
		}

		return FSEventTestResult(
			totalEvents: events.count,
			isChronological: isChronological,
			eventIDRange: eventIDs.isEmpty ? nil : (eventIDs.min()!, eventIDs.max()!),
			timingStats: timingStats
		)
	}
}

// MARK: - Unsafe Implementation (Educational)

/// UNSAFE: Non-thread-safe event collector to demonstrate race conditions
public final class UnsafeEventCollector: FSEventCollector {
	/// ⚠️ NO LOCKING: This is the critical flaw!
	private var events: [(eventID: FSEventStreamEventId, path: String, receivedAt: Date)] = []

	public init() {}

	/// UNSAFE: Non-thread-safe method that can cause data corruption
	public func recordEvent(eventID: FSEventStreamEventId, path: String) {
		// ⚠️ RACE CONDITION: Multiple threads can corrupt this array
		events.append((eventID: eventID, path: path, receivedAt: Date()))

		// Add small delay to increase race condition window
		Thread.sleep(forTimeInterval: 0.00001)  // 10 microseconds
	}

	/// UNSAFE: Non-thread-safe analysis that may read corrupted data
	public func analyzeEvents() -> FSEventTestResult {
		// ⚠️ READING DURING CONCURRENT MODIFICATIONS!
		let eventIDs = events.map { $0.eventID }
		let sortedIDs = eventIDs.sorted()
		let isChronological = eventIDs == sortedIDs

		var timingStats: FSEventTimingStats?
		if events.count > 1 {
			let intervals = zip(events, events.dropFirst()).map { current, next in
				next.receivedAt.timeIntervalSince(current.receivedAt)
			}
			timingStats = FSEventTimingStats(
				averageInterval: intervals.reduce(0, +) / Double(intervals.count),
				minInterval: intervals.min() ?? 0,
				maxInterval: intervals.max() ?? 0
			)
		}

		return FSEventTestResult(
			totalEvents: events.count,  // ⚠️ May be wrong due to race conditions
			isChronological: isChronological,
			eventIDRange: eventIDs.isEmpty ? nil : (eventIDs.min()!, eventIDs.max()!),
			timingStats: timingStats,
			possiblyCorrupted: true
		)
	}
}

// MARK: - Specialized Event ID Collector

/// Event collector that tracks FSEventStreamEventId for ordering analysis
public final class EventIDCollector: FSEventCollector, @unchecked Sendable {
	private let lock = NSLock()
	private var eventIDs: [FSEventStreamEventId] = []
	private var maxCount: Int?

	public init(maxCount: Int? = nil) {
		self.maxCount = maxCount
	}

	public func recordEvent(eventID: FSEventStreamEventId, path: String) {
		lock.lock()
		defer { lock.unlock() }
		eventIDs.append(eventID)
	}

	/// Get the collected event IDs
	public func getEventIDs() -> [FSEventStreamEventId] {
		lock.lock()
		defer { lock.unlock() }
		return eventIDs
	}

	/// Check if we've reached the maximum count
	public func hasReachedMaxCount() -> Bool {
		guard let maxCount = maxCount else { return false }
		lock.lock()
		defer { lock.unlock() }
		return eventIDs.count >= maxCount
	}

	public func analyzeEvents() -> FSEventTestResult {
		lock.lock()
		defer { lock.unlock() }

		let sortedIDs = eventIDs.sorted()
		let isChronological = eventIDs == sortedIDs

		return FSEventTestResult(
			totalEvents: eventIDs.count,
			isChronological: isChronological,
			eventIDRange: eventIDs.isEmpty ? nil : (eventIDs.min()!, eventIDs.max()!),
			timingStats: nil  // No timing info for this collector
		)
	}

	/// Get detailed ordering analysis for regression testing
	public func getOrderingAnalysis() -> EventIDOrderingAnalysis {
		lock.lock()
		defer { lock.unlock() }

		let sortedIDs = eventIDs.sorted()
		let isOrdered = eventIDs == sortedIDs

		let outOfOrderPositions: [Int] = zip(eventIDs.indices, zip(eventIDs, sortedIDs))
			.compactMap { index, pair in
				pair.0 != pair.1 ? index : nil
			}

		return EventIDOrderingAnalysis(
			eventIDs: eventIDs,
			sortedIDs: sortedIDs,
			isOrdered: isOrdered,
			outOfOrderPositions: outOfOrderPositions
		)
	}
}

/// Detailed analysis of event ID ordering for regression tests
public struct EventIDOrderingAnalysis {
	public let eventIDs: [FSEventStreamEventId]
	public let sortedIDs: [FSEventStreamEventId]
	public let isOrdered: Bool
	public let outOfOrderPositions: [Int]

	public var outOfOrderCount: Int {
		return outOfOrderPositions.count
	}

	public func printDetailedReport(filePrefix: String) {
		print(
			"""

			📊 EVENT ORDERING ANALYSIS
			=========================
			Events received: \(eventIDs.count) 
			Events in chronological order: \(isOrdered ? "✅ YES" : "❌ NO")
			First 5 Event IDs: \(Array(eventIDs.prefix(5)))
			Event ID range: \(eventIDs.first ?? 0)...\(eventIDs.last ?? 0)
			"""
		)

		if !isOrdered {
			print(
				"""

				⚠️  EVENT REORDERING DETECTED!
				Out of order positions: \(outOfOrderCount)
				Positions with reordering: \(Array(outOfOrderPositions.prefix(10)))
				"""
			)

			// Show first few examples of reordering
			let examples = zip(eventIDs.indices, zip(eventIDs, sortedIDs))
				.filter { _, pair in pair.0 != pair.1 }
				.prefix(5)

			for (position, (received, expected)) in examples {
				let filename = String(format: "\(filePrefix)_%03d.txt", position)
				print("  Position \(position) (\(filename)): got \(received), expected \(expected)")
			}
		}

		print("")
	}
}
