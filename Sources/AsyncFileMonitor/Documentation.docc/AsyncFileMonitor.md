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
let eventStream = try FolderContentMonitor.makeStream(url: URL(fileURLWithPath: "/path/to/monitor/"))

// Use async/await to process events
for await event in eventStream {
    print("File changed: \(event.filename) at \(event.eventPath)")
    print("Change type: \(event.change)")
}
```

### Monitoring Multiple Paths

```swift
let eventStream = try FolderContentMonitor.makeStream(paths: [
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
let eventStream = try FolderContentMonitor.makeStream(
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

### Multiple Concurrent Streams

Each stream owns its own FSEventStream and is fully independent: one ending does not affect the others, and each coalesces events on its own. Event IDs and batch boundaries can therefore differ between streams watching the same path.

```swift
let uiUpdateStream = try FolderContentMonitor.makeStream(url: documentsURL)
let backupStream = try FolderContentMonitor.makeStream(url: documentsURL)
let logStream = try FolderContentMonitor.makeStream(url: documentsURL)

Task {
    for await event in uiUpdateStream {
        await updateUI(for: event)
    }
}

Task {
    for await event in backupStream {
        guard event.change.contains(.modified) else { continue }
        await backupFile(event.url)
    }
}

Task {
    for await event in logStream {
        logger.info("File changed: \(event.filename)")
    }
}
```

## Topics

### Essential Types

- ``FolderContentMonitor``
- ``FolderContentChangeEvent``
- ``Change``
- ``StreamCondition``

## Architecture

AsyncFileMonitor uses a direct AsyncStream architecture. Each stream owns one FSEventStream:

```
FSEventStream (C API) → C Callback → AsyncStream Continuation
```

The flow never crosses a Task boundary, which is what would let Swift concurrency reorder events.

### Key Design Benefits

The direct AsyncStream architecture provides these benefits:

**Consistent Event Ordering**: Events flow directly from FSEventStream callbacks to AsyncStream continuations without Task boundaries where reordering can occur.

**Automatic Lifecycle Management**: An FSEventStream is created synchronously when the factory returns and released when the stream terminates — whether the consumer breaks, cancels, or drops it without iterating.

**Reduced Overhead**: Avoids actor isolation and Task scheduling overhead compared to approaches that use Swift concurrency primitives.
