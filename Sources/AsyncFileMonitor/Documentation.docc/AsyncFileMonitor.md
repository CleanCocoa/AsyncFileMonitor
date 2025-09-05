# AsyncFileMonitor

Swift Package for monitoring file system events using CoreFoundation's FSEvents API with async/await support.

## Overview

AsyncFileMonitor is the successor to RxFileMonitor, providing file monitoring capabilities with Swift 6 concurrency support. It uses Apple's native FSEvents API for file system monitoring with async/await integration.

### Features

- **Async/await Support**: Uses `AsyncStream` for async/await integration
- **Swift 6 Compatible**: Concurrency support with `Sendable` conformance  
- **FSEvents Integration**: File system monitoring using Apple's native FSEvents API
- **Flexible Monitoring**: Monitor single files, directories, or multiple paths
- **Event Filtering**: Event information with detailed change flags
- **Automatic Resource Management**: `FSEventStream` lifecycle management

## Getting Started

### Basic Usage

```swift
import AsyncFileMonitor

// Monitor a directory
let eventStream = FolderContentMonitor.makeStream(url: URL(fileURLWithPath: "/path/to/monitor/"))

// Use async/await to process events
for await event in eventStream {
    print("File changed: \(event.filename) at \(event.eventPath)")
    print("Change type: \(event.change)")
}
```

### Monitoring Multiple Paths

```swift
let eventStream = FolderContentMonitor.makeStream(paths: [
    "/Users/you/Documents", 
    "/Users/you/Desktop"
])

for await event in eventStream {
    print("Change in \(event.eventPath): \(event.change)")
}
```

### Advanced Configuration

```swift
// Create a stream with custom configuration
let eventStream = FolderContentMonitor.makeStream(
    url: URL(fileURLWithPath: "/Users/you/Documents"),
    latency: 0.5  // Coalesce rapid changes
)

// Process file events with filtering
for await event in eventStream {
    // Filter for file changes only
    guard event.change.contains(.isFile) else { continue }
    
    // Skip system files
    guard event.filename != ".DS_Store" else { continue }
    
    print("Document changed: \(event.filename)")
}
```

## Topics

### Essential Types

- ``FolderContentMonitor``
- ``FolderContentChangeEvent``
- ``Change``

### Monitoring and Streams

- ``StreamLifecycleEvent``
- ``MulticastAsyncStream``

## Architecture

AsyncFileMonitor uses a direct AsyncStream architecture:

```
FSEventStream (C API) → C Callback → MulticastAsyncStream.send() → AsyncStream Continuations
```

This direct flow avoids Swift concurrency Task scheduling that can cause event reordering.

### Key Design Benefits

The direct AsyncStream architecture provides these benefits:

**Consistent Event Ordering**: Events flow directly from FSEventStream callbacks to AsyncStream continuations without Task boundaries where reordering can occur.

**Resource Sharing**: Multiple `AsyncStream` instances share a single FSEventStream through the MulticastAsyncStream broadcaster.

**Automatic Lifecycle Management**: FSEventStreams start when the first client connects and stop when the last disconnects.

**Thread Safety**: Swift 6 Mutex provides synchronization without actor overhead.

**Ordered Subscribers**: OrderedDictionary preserves subscriber registration order for deterministic event delivery.

**Reduced Overhead**: Avoids actor isolation and Task scheduling overhead compared to approaches that use Swift concurrency primitives.
