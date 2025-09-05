//
//  MulticastAsyncStream.swift
//  AsyncFileMonitor
//
//  Created by Christian Tietze on 2025-09-05.
//  Copyright © 2025 Christian Tietze (AsyncFileMonitor modernization)
//
//  Reference: 20250905T073442
//
//  Modern Swift 6 multicast AsyncStream implementation using Mutex for thread-safe
//  event broadcasting to multiple subscribers with preserved registration order.
//

import Foundation
import OrderedCollections
import Synchronization

/// Stream lifecycle events for automatic start/stop management.
///
/// These events are emitted to signal when the first stream is added
/// or the last stream is removed, enabling automatic resource management.
public enum StreamLifecycleEvent: Sendable {
	/// Emitted when the first stream is added to an empty multicast stream.
	case firstStreamAdded

	/// Emitted when the last stream is removed from the multicast stream.
	case lastStreamRemoved
}

/// A multicast AsyncStream implementation that preserves subscriber order using OrderedDictionary.
///
/// This provides better ordering guarantees than Dictionary-based approaches by maintaining
/// the registration order of continuations. Uses Swift 6 Mutex for thread-safe synchronization.
/// Events are broadcast directly from FSEventStream callbacks without any Task scheduling,
/// eliminating Swift concurrency reordering issues.
///
/// ## Key Benefits
/// - **Perfect event ordering**: Direct callback → continuation flow without Task boundaries
/// - **Ordered subscribers**: Uses OrderedDictionary to maintain registration order
/// - **Thread-safe**: Swift 6 Mutex provides safe synchronization
/// - **Lifecycle management**: Automatic start/stop based on subscriber count
/// - **High performance**: No actor isolation or Task scheduling overhead
public final class MulticastAsyncStream<T>: Sendable where T: Sendable {
	private let continuations: Mutex<OrderedDictionary<UUID, AsyncStream<T>.Continuation>>
	private let lifecycleContinuation: Mutex<AsyncStream<StreamLifecycleEvent>.Continuation?>
	private let streamCount: Mutex<Int>

	public init() {
		self.continuations = Mutex(OrderedDictionary<UUID, AsyncStream<T>.Continuation>())
		self.lifecycleContinuation = Mutex(nil)
		self.streamCount = Mutex(0)
	}

	/// Create a stream that emits lifecycle events (first stream added, last stream removed).
	///
	/// - Returns: An `AsyncStream` of `StreamLifecycleEvent` values
	public func makeLifecycleStream() -> AsyncStream<StreamLifecycleEvent> {
		let (stream, continuation) = AsyncStream<StreamLifecycleEvent>.makeStream()
		lifecycleContinuation.withLock { lifecycleCont in
			lifecycleCont = continuation
		}
		return stream
	}

	/// Create a new `AsyncStream` that will receive all broadcast elements.
	///
	/// This method automatically manages the stream's lifecycle, removing it from
	/// the multicast when the stream terminates and emitting lifecycle events.
	///
	/// - Returns: An `AsyncStream` that will receive all broadcast elements
	public func makeStream() -> AsyncStream<T> {
		let id = UUID()
		let (stream, continuation) = AsyncStream<T>.makeStream()

		// Check if this is the first stream
		let wasEmpty = continuations.withLock { dict in
			let isEmpty = dict.isEmpty
			dict[id] = continuation
			return isEmpty
		}

		// Update stream count
		streamCount.withLock { count in
			count += 1
		}

		// Set up cleanup when stream terminates
		continuation.onTermination = { [weak self] _ in
			guard let self = self else { return }

			let becameEmpty = self.continuations.withLock { dict in
				_ = dict.removeValue(forKey: id)
				return dict.isEmpty
			}

			self.streamCount.withLock { count in
				count = max(0, count - 1)
			}

			if becameEmpty {
				self.lifecycleContinuation.withLock { lifecycleCont in
					_ = lifecycleCont?.yield(.lastStreamRemoved)
				}
			}
		}

		// Emit first stream added event if this is the first stream
		if wasEmpty {
			lifecycleContinuation.withLock { lifecycleCont in
				_ = lifecycleCont?.yield(.firstStreamAdded)
			}
		}

		return stream
	}

	/// Broadcast an element to all registered continuations.
	///
	/// This method is called directly from FSEventStream callbacks and yields
	/// events immediately to all subscribers without any Task scheduling,
	/// ensuring perfect event ordering.
	///
	/// - Parameter value: The element to broadcast to all active streams
	public func send(_ value: T) {
		let currentContinuations = continuations.withLock { dict in
			Array(dict.values)
		}

		for continuation in currentContinuations {
			continuation.yield(value)
		}
	}

	/// Get the current number of active stream subscribers.
	///
	/// - Returns: The number of currently registered stream continuations
	public var currentStreamCount: Int {
		streamCount.withLock { $0 }
	}
}
