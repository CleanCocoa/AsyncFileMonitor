# AsyncFileMonitor

Modern async/await Swift Package for monitoring file system events using CoreFoundation's FSEvents API.

## Overview

AsyncFileMonitor is the modernized successor to RxFileMonitor, providing the same powerful file monitoring capabilities with Swift 6 concurrency support. It uses Apple's native FSEvents API for efficient file system monitoring with natural async/await integration.

### Features

- **Modern Async/await**: Uses `AsyncStream` for natural async/await integration
- **Swift 6 Ready**: Full concurrency support with `Sendable` conformance  
- **FSEvents Integration**: Efficient file system monitoring using Apple's native FSEvents API
- **Flexible Monitoring**: Monitor single files, directories, or multiple paths
- **Event Filtering**: Rich event information with detailed change flags
- **Resource Efficient**: Automatic `FSEventStream` lifecycle management

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
    latency: 0.5,  // Coalesce rapid changes
    qos: .userInitiated
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

## Architecture

AsyncFileMonitor uses a simple, efficient architecture:

```
FolderContentMonitor (actor - public API & FSEventStream management)
    ↓
StreamRegistrar (actor - continuation management & lifecycle)
    ↓
OrderedDictionary<Int, Continuation> (continuation storage)
```

### Key Design Benefits

The architecture provides several important benefits for efficient file system monitoring:

Resource sharing between multiple `AsyncStream` instances allows multiple consumers to monitor the same path without creating redundant FSEventStreams. Automatic lifecycle management ensures FSEventStreams start when the first client connects and stop when the last disconnects. Thread safety through isolated actors prevents data races and ensures proper resource coordination. The clean, simple API surface makes it easy to integrate file monitoring into any Swift application.
