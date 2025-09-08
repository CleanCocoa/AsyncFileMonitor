#if canImport(Clibuv)
import Clibuv
import Collections
import Foundation

/// Linux implementation of file system monitoring using libuv's fs_event functionality.
/// Provides the same AsyncStream-based API as the macOS FSEvents implementation.
public final class LibuvFileMonitor: Sendable {
	private let loop: UnsafeMutablePointer<uv_loop_t>
	private let paths: [String]
	private let latency: TimeInterval
	private let multicastStream: MulticastAsyncStream<FolderContentChangeEvent>

	public init(urls: [URL], latency: TimeInterval = 0.0) {
		self.paths = urls.map { $0.path }
		self.latency = latency
		self.multicastStream = MulticastAsyncStream()

		// Initialize libuv event loop
		self.loop = UnsafeMutablePointer<uv_loop_t>.allocate(capacity: 1)
		uv_loop_init(loop)

		// Start monitoring in background thread
		Task.detached { [weak self] in
			await self?.runEventLoop()
		}
	}

	deinit {
		uv_loop_close(loop)
		loop.deallocate()
	}

	/// Create a new AsyncStream for monitoring file system events.
	public func makeStream() -> AsyncStream<FolderContentChangeEvent> {
		return multicastStream.makeStream()
	}

	/// Static convenience method matching macOS API
	public static func makeStream(url: URL, latency: TimeInterval = 0.0) -> AsyncStream<FolderContentChangeEvent> {
		let monitor = LibuvFileMonitor(urls: [url], latency: latency)
		return monitor.makeStream()
	}

	/// Static convenience method for multiple paths
	public static func makeStream(paths: [String], latency: TimeInterval = 0.0) -> AsyncStream<FolderContentChangeEvent>
	{
		let urls = paths.map { URL(fileURLWithPath: $0) }
		let monitor = LibuvFileMonitor(urls: urls, latency: latency)
		return monitor.makeStream()
	}

	/// Run the libuv event loop to monitor file system changes
	private func runEventLoop() async {
		// Set up fs_event handles for each path
		var handles: [UnsafeMutablePointer<uv_fs_event_t>] = []

		for path in paths {
			let handle = UnsafeMutablePointer<uv_fs_event_t>.allocate(capacity: 1)
			uv_fs_event_init(loop, handle)

			// Store reference to self in handle data for callback access
			let context = EventContext(monitor: self, path: path)
			let contextPtr = Unmanaged.passUnretained(context).toOpaque()
			handle.pointee.data = contextPtr

			// Start monitoring the path
			path.withCString { cPath in
				uv_fs_event_start(handle, fsEventCallback, cPath, 0)
			}

			handles.append(handle)
		}

		// Run the event loop
		uv_run(loop, UV_RUN_DEFAULT)

		// Cleanup handles
		for handle in handles {
			uv_close(UnsafeMutablePointer<uv_handle_t>(handle)) { handlePtr in
				handlePtr?.deallocate()
			}
		}
	}
}

/// Context object to pass data to libuv callbacks
private final class EventContext {
	let monitor: LibuvFileMonitor
	let path: String

	init(monitor: LibuvFileMonitor, path: String) {
		self.monitor = monitor
		self.path = path
	}
}

/// libuv fs_event callback function
private func fsEventCallback(
	handle: UnsafeMutablePointer<uv_fs_event_t>?,
	filename: UnsafePointer<CChar>?,
	events: CInt,
	status: CInt
) {
	guard let handle = handle,
		let contextPtr = handle.pointee.data
	else { return }

	let context = Unmanaged<EventContext>.fromOpaque(contextPtr).takeUnretainedValue()

	if status < 0 {
		print("File monitoring error: \(String(cString: uv_strerror(status)))")
		return
	}

	let filenameStr = filename.map { String(cString: $0) } ?? ""
	let eventPath = context.path
	let fullPath = eventPath.hasSuffix("/") ? eventPath + filenameStr : eventPath + "/" + filenameStr

	// Convert libuv events to our Change flags
	var change = Change()

	if events & UV_CHANGE != 0 {
		change.insert(.modified)
	}
	if events & UV_RENAME != 0 {
		change.insert(.renamed)
	}

	// Determine file type by checking if path exists and is directory
	let url = URL(fileURLWithPath: fullPath)
	var isDirectory: ObjCBool = false
	let exists = FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDirectory)

	if exists {
		if isDirectory.boolValue {
			change.insert(.isDirectory)
		} else {
			change.insert(.isFile)
		}
	} else {
		// File was removed
		change.insert(.removed)
		change.insert(.isFile)  // Assume file unless we have better info
	}

	let event = FolderContentChangeEvent(
		eventId: UInt64.random(in: 0...UInt64.max),
		eventPath: eventPath,
		eventFlags: UInt32(events),
		change: change
	)

	context.monitor.multicastStream.send(event)
}

// MARK: - Supporting Types

/// Multicast AsyncStream implementation for Linux
public final class MulticastAsyncStream<Element>: Sendable {
	private let mutex = Mutex<State<Element>>()

	private struct State<Element> {
		var subscribers: OrderedDictionary<UUID, AsyncStream<Element>.Continuation> = [:]
		var isFinished = false
	}

	public init() {
		mutex.withLock { $0 = State() }
	}

	public func makeStream() -> AsyncStream<Element> {
		let id = UUID()

		return AsyncStream<Element> { continuation in
			mutex.withLock { state in
				if state.isFinished {
					continuation.finish()
				} else {
					state.subscribers[id] = continuation
				}
			}

			continuation.onTermination = { _ in
				self.mutex.withLock { state in
					state.subscribers.removeValue(forKey: id)
				}
			}
		}
	}

	public func send(_ element: Element) {
		mutex.withLock { state in
			for (_, continuation) in state.subscribers {
				continuation.yield(element)
			}
		}
	}

	public func finish() {
		mutex.withLock { state in
			for (_, continuation) in state.subscribers {
				continuation.finish()
			}
			state.subscribers.removeAll()
			state.isFinished = true
		}
	}
}

/// Thread-safe mutex wrapper
private final class Mutex<Value>: @unchecked Sendable {
	private let storage: UnsafeMutablePointer<Value>
	private let lock = NSLock()

	init(_ value: Value) {
		storage = UnsafeMutablePointer.allocate(capacity: 1)
		storage.initialize(to: value)
	}

	deinit {
		storage.deinitialize(count: 1)
		storage.deallocate()
	}

	func withLock<Result>(_ body: (inout Value) -> Result) -> Result {
		lock.lock()
		defer { lock.unlock() }
		return body(&storage.pointee)
	}
}

#endif
