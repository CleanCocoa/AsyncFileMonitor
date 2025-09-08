//
//  AsyncFileMonitor.swift
//  AsyncFileMonitor
//
//  Created by Christian Tietze on 2025-09-06
//  Copyright © 2025 Christian Tietze (AsyncFileMonitor cross-platform wrapper)
//

import Foundation

#if os(macOS)
import AsyncFileMonitorFSEvents
public typealias FolderContentChangeEvent = AsyncFileMonitorFSEvents.FolderContentChangeEvent
public typealias Change = AsyncFileMonitorFSEvents.Change
#elseif os(Linux)
import AsyncFileMonitorLinux
public typealias FolderContentChangeEvent = AsyncFileMonitorLinux.FolderContentChangeEvent
public typealias Change = AsyncFileMonitorLinux.Change
#endif

/// Cross-platform file monitoring API.
///
/// This is a convenience wrapper that provides a unified interface for file monitoring
/// across different platforms, using the appropriate underlying implementation.
public enum AsyncFileMonitor {

	/// Monitor multiple paths for file system changes.
	///
	/// - Parameters:
	///   - paths: Array of path strings to monitor for changes.
	///   - latency: The latency for coalescing events.
	/// - Returns: An async stream of folder content change events.
	public static func monitor(paths: [String], latency: TimeInterval = 0.0) -> AsyncStream<FolderContentChangeEvent> {
		#if os(macOS)
		return FolderContentMonitor.makeStream(paths: paths, latency: latency)
		#elseif os(Linux)
		return LibuvFileMonitor.makeStream(paths: paths, latency: latency)
		#else
		#error("No file monitoring implementation available for this platform")
		#endif
	}

	/// Monitor a single path for file system changes.
	///
	/// - Parameters:
	///   - url: The URL to monitor for changes.
	///   - latency: The latency for coalescing events.
	/// - Returns: An async stream of folder content change events.
	public static func monitor(url: URL, latency: TimeInterval = 0.0) -> AsyncStream<FolderContentChangeEvent> {
		return monitor(paths: [url.path], latency: latency)
	}
}
