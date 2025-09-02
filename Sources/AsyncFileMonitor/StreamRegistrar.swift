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
public enum StreamLifecycleEvent: Sendable {
	case firstStreamAdded
	case lastStreamRemoved
}

/// Manages multiple `AsyncStream` continuations for broadcasting elements to multiple consumers.
///
/// Uses `OrderedDictionary` to maintain registration order when broadcasting.
/// Emits lifecycle events when transitioning between 0 and 1+ streams.
actor StreamRegistrar<Element> where Element: Sendable {
	private var count = 0
	private var continuations = OrderedDictionary<Int, AsyncStream<Element>.Continuation>()
	private var lifecycleContinuation: AsyncStream<StreamLifecycleEvent>.Continuation?

	/// Number of active streams.
	var streamCount: Int { continuations.count }

	deinit {
		for (_, continuation) in continuations {
			continuation.finish()
		}
		lifecycleContinuation?.finish()
	}

	/// Create a stream that emits lifecycle events (first stream added, last stream removed).
	func makeLifecycleStream() -> AsyncStream<StreamLifecycleEvent> {
		let (stream, continuation) = AsyncStream<StreamLifecycleEvent>.makeStream()
		lifecycleContinuation = continuation
		return stream
	}

	/// Create a new AsyncStream that will receive all yielded elements.
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
