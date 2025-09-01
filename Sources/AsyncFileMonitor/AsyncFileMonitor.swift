//
//  AsyncFileMonitor.swift
//  AsyncFileMonitor
//
//  Created by Christian Tietze on 08/11/16.
//  Copyright © 2025 Christian Tietze (based on original RxFileMonitor concepts)
//

import Foundation

extension FolderContentMonitor {

	/// Creates an `AsyncStream` of folder content change events.
	///
	/// This provides a modern async/await interface to monitor file system changes.
	/// The stream will automatically start monitoring when iterated and clean up
	/// when the iteration is cancelled or completes.
	///
	/// Usage:
	/// ```swift
	/// let monitor = FolderContentMonitor(url: URL(fileURLWithPath: "/path/to/watch"))
	///
	/// for await event in monitor.events {
	///     print("File changed: \(event.filename)")
	/// }
	/// ```
	public var events: AsyncStream<FolderContentChangeEvent> {
		AsyncStream { continuation in
			// Store the original callback to restore it later
			let originalCallback = self.callback

			// Set up our callback to send events to the continuation
			self.callback = { @Sendable event in
				originalCallback?(event)
				continuation.yield(event)
			}

			// Start monitoring if not already started
			if !self.hasStarted {
				self.start()
			}

			// Handle cancellation
			continuation.onTermination = { @Sendable [weak self] _ in
				self?.stop()
				self?.callback = originalCallback
			}
		}
	}

	/// Creates an `AsyncThrowingStream` of folder content change events.
	///
	/// This variant can handle errors that might occur during monitoring.
	/// Currently, it behaves the same as the non-throwing version but provides
	/// the infrastructure for future error handling.
	public var throwingEvents: AsyncThrowingStream<FolderContentChangeEvent, Error> {
		AsyncThrowingStream { continuation in
			// Store the original callback to restore it later
			let originalCallback = self.callback

			// Set up our callback to send events to the continuation
			self.callback = { @Sendable event in
				originalCallback?(event)
				continuation.yield(event)
			}

			// Start monitoring if not already started
			if !self.hasStarted {
				self.start()
			}

			// Handle cancellation
			continuation.onTermination = { @Sendable [weak self] _ in
				self?.stop()
				self?.callback = originalCallback
			}
		}
	}
}

/// Convenience functions for creating file monitors
extension AsyncFileMonitor {

	/// Create a file monitor for a single URL
	///
	/// - Parameters:
	///   - url: The file or directory URL to monitor
	///   - sinceWhen: Reference event for the subscription. Default is `kFSEventStreamEventIdSinceNow`
	///   - latency: Interval (in seconds) to allow coalescing events. Default is 0
	/// - Returns: A configured `FolderContentMonitor`
	public static func monitor(
		url: URL,
		sinceWhen: FSEventStreamEventId = FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
		latency: CFTimeInterval = 0
	) -> FolderContentMonitor {
		FolderContentMonitor(url: url, sinceWhen: sinceWhen, latency: latency)
	}

	/// Create a file monitor for multiple paths
	///
	/// - Parameters:
	///   - paths: Array of file or directory paths to monitor
	///   - sinceWhen: Reference event for the subscription. Default is `kFSEventStreamEventIdSinceNow`
	///   - latency: Interval (in seconds) to allow coalescing events. Default is 0
	/// - Returns: A configured `FolderContentMonitor`
	public static func monitor(
		paths: [String],
		sinceWhen: FSEventStreamEventId = FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
		latency: CFTimeInterval = 0
	) -> FolderContentMonitor {
		FolderContentMonitor(pathsToWatch: paths, sinceWhen: sinceWhen, latency: latency)
	}
}

/// Namespace for AsyncFileMonitor functionality
public enum AsyncFileMonitor {
	// This enum serves as a namespace for static functions
}
