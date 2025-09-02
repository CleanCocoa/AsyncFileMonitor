//
//  AsyncFileMonitor.swift
//  AsyncFileMonitor
//
//  Created by Christian Tietze on 08/11/16.
//  Copyright © 2025 Christian Tietze (based on original RxFileMonitor concepts)
//

import Foundation

/// Convenience functions for creating file monitors and async streams
public enum AsyncFileMonitor {

	/// Monitor a single URL and return an AsyncStream of file system events.
	///
	/// - Parameters:
	///   - url: The file or directory URL to monitor
	///   - sinceWhen: Reference event for the subscription. Default is `kFSEventStreamEventIdSinceNow`
	///   - latency: Interval (in seconds) to allow coalescing events. Default is 0
	///   - qos: Quality of service for the monitoring queue. Default is `userInteractive` for UI responsiveness
	/// - Returns: An AsyncStream of FolderContentChangeEvent objects
	public static func monitor(
		url: URL,
		sinceWhen: FSEventStreamEventId = FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
		latency: CFTimeInterval = 0,
		qos: DispatchQoS = .userInteractive
	) -> AsyncStream<FolderContentChangeEvent> {
		FolderContentMonitor.makeStream(url: url, sinceWhen: sinceWhen, latency: latency, qos: qos)
	}

	/// Monitor multiple paths and return an AsyncStream of file system events.
	///
	/// - Parameters:
	///   - paths: Array of file or directory paths to monitor
	///   - sinceWhen: Reference event for the subscription. Default is `kFSEventStreamEventIdSinceNow`
	///   - latency: Interval (in seconds) to allow coalescing events. Default is 0
	///   - qos: Quality of service for the monitoring queue. Default is `userInteractive` for UI responsiveness
	/// - Returns: An AsyncStream of FolderContentChangeEvent objects
	public static func monitor(
		paths: [String],
		sinceWhen: FSEventStreamEventId = FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
		latency: CFTimeInterval = 0,
		qos: DispatchQoS = .userInteractive
	) -> AsyncStream<FolderContentChangeEvent> {
		FolderContentMonitor.makeStream(paths: paths, sinceWhen: sinceWhen, latency: latency, qos: qos)
	}
}
