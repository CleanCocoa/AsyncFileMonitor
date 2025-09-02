//
//  StreamRegistrar.swift
//  AsyncFileMonitor
//
//  Created by Christian Tietze on 2025-09-02.
//  Copyright © 2025 Christian Tietze (AsyncFileMonitor modernization)
//
//  Helper class to manage multiple AsyncStream continuations for event broadcasting.
//

import Collections
import Foundation

/// Stream lifecycle events for automatic start/stop management.
///
/// These events are emitted by the stream registrar to signal when the first stream is added
/// or the last stream is removed, enabling automatic resource management.
public enum StreamLifecycleEvent: Sendable {
	/// Emitted when the first stream is added to an empty registrar.
	case firstStreamAdded

	/// Emitted when the last stream is removed from the registrar.
	case lastStreamRemoved
}

/// Manages multiple `AsyncStream` continuations for broadcasting elements to multiple consumers.
///
/// Uses `OrderedDictionary` to maintain registration order when broadcasting.
/// Emits ``StreamLifecycleEvent`` events when transitioning between `0` and `1+` streams.
actor StreamRegistrar<Element> where Element: Sendable {
	private var count = 0
	private var continuations = OrderedDictionary<Int, AsyncStream<Element>.Continuation>()
	private var lifecycleContinuation: AsyncStream<StreamLifecycleEvent>.Continuation?

	/// Number of active streams.
	///
	/// This property provides a count of currently registered stream continuations.
	var streamCount: Int { continuations.count }

	deinit {
		for (_, continuation) in continuations {
			continuation.finish()
		}
		lifecycleContinuation?.finish()
	}

	/// Create a stream that emits lifecycle events (first stream added, last stream removed).
	///
	/// - Returns: An `AsyncStream` of ``StreamLifecycleEvent`` values
	func makeLifecycleStream() -> AsyncStream<StreamLifecycleEvent> {
		let (stream, continuation) = AsyncStream<StreamLifecycleEvent>.makeStream()
		lifecycleContinuation = continuation
		return stream
	}

	/// Create a new `AsyncStream` that will receive all yielded elements.
	///
	/// This method automatically manages the stream's lifecycle, removing it from
	/// the registrar when the stream terminates.
	///
	/// - Returns: An `AsyncStream` that will receive all broadcast elements
	func makeStream() -> AsyncStream<Element> {
		count += 1
		let id = count
		let (stream, continuation) = AsyncStream<Element>.makeStream()

		// Emit first stream added event if this is the first stream
		let wasEmpty = continuations.isEmpty

		continuation.onTermination = { [weak self] _ in
			// Might as well unwrap self here because in the `await` statement below, everything to
			// the right of it will be strongly referenced anyway.
			guard let self else { return }
			Task {
				await self.removeContinuation(id: id)
			}
		}
		continuations[id] = continuation

		if wasEmpty {
			lifecycleContinuation?.yield(.firstStreamAdded)
		}

		return stream
	}

	/// Broadcast an element to all registered continuations.
	///
	/// - Parameter element: The element to broadcast to all active streams
	func yield(_ element: Element) {
		for (_, continuation) in continuations {
			continuation.yield(element)
		}
	}

	private func removeContinuation(id: Int) {
		continuations.removeValue(forKey: id)

		// Emit last stream removed event if this was the last stream
		if continuations.isEmpty {
			lifecycleContinuation?.yield(.lastStreamRemoved)
		}
	}
}
