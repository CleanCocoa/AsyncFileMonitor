# Getting Started with AsyncFileMonitor

Learn how to monitor file system changes using AsyncFileMonitor's modern async/await API.

## Overview

AsyncFileMonitor provides a simple yet powerful API for monitoring file system events. This guide will walk you through the basic concepts and common usage patterns.

## Installation

### Swift Package Manager

Add AsyncFileMonitor to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/AsyncFileMonitor.git", from: "1.0.0")
]
```

### Xcode Integration

1. File > Add Package Dependencies
2. Enter the repository URL
3. Select your target

## Basic File Monitoring

The simplest way to monitor files is using ``FolderContentMonitor``:

```swift
import AsyncFileMonitor

// Monitor a single directory
let stream = FolderContentMonitor.makeStream(url: URL(fileURLWithPath: "/Users/you/Documents"))

for await event in stream {
    print("File changed: \(event.filename)")
    print("Path: \(event.eventPath)")
    print("Change type: \(event.change)")
}
```

## Understanding Events

Each file system change generates a ``FolderContentChangeEvent`` containing:

- **eventID**: Unique identifier for the event
- **eventPath**: Full path to the changed item  
- **change**: ``Change`` flags describing what changed

### Common Change Types

```swift
for await event in stream {
    if event.change.contains(.created) {
        print("File created: \(event.filename)")
    }
    
    if event.change.contains(.modified) {
        print("File modified: \(event.filename)")
    }
    
    if event.change.contains(.removed) {
        print("File removed: \(event.filename)")
    }
    
    if event.change.contains(.isDirectory) {
        print("Directory changed: \(event.filename)")
    }
}
```

## Filtering Events

Filter events to focus on what matters to your application:

```swift
// Only monitor file modifications (not directories)
for await event in stream 
where event.change.contains(.isFile) && event.change.contains(.modified) {
    await processModifiedFile(event.url)
}

// Skip system files
for await event in stream {
    guard !event.filename.hasPrefix(".") else { continue }
    await handleUserFile(event)
}
```

## Task-Based Monitoring

Use Swift's structured concurrency for proper resource management:

```swift
let monitorTask = Task {
    let stream = FolderContentMonitor.makeStream(url: documentsURL)
    
    for await event in stream {
        await handleFileChange(event)
    }
}

// Stop monitoring when done
defer { monitorTask.cancel() }
```

## Multiple Paths

Monitor several directories simultaneously:

```swift
let stream = FolderContentMonitor.makeStream(paths: [
    "/Users/you/Documents",
    "/Users/you/Desktop", 
    "/Users/you/Downloads"
])

for await event in stream {
    print("Change detected in: \(event.eventPath)")
}
```

## Advanced Configuration

For fine-tuned control, use ``FolderContentMonitor`` directly:

```swift
let monitor = FolderContentMonitor(
    url: URL(fileURLWithPath: "/Users/you/Documents"),
    latency: 0.5,  // Wait 0.5 seconds to coalesce events
    qos: .userInitiated  // Quality of service level
)

let stream = await monitor.makeStream()

for await event in stream {
    // Handle events with custom configuration
    await processEvent(event)
}
```

### Latency Configuration

Control event coalescing to reduce noise:

```swift
// No latency - all events reported immediately (can be noisy)
let stream = FolderContentMonitor.makeStream(url: url, latency: 0.0)

// 1-second latency - coalesces rapid changes
let stream = FolderContentMonitor.makeStream(url: url, latency: 1.0)
```

## Error Handling

AsyncStream handles most errors gracefully, but you should validate paths:

```swift
let path = "/path/to/monitor"
let url = URL(fileURLWithPath: path)

// Verify path exists before monitoring
guard FileManager.default.fileExists(atPath: path) else {
    print("Path does not exist: \(path)")
    return
}

let stream = FolderContentMonitor.makeStream(url: url)
```

## Next Steps

- Explore the ``Change`` flags for detailed event information
- Learn about ``FolderContentMonitor`` for advanced use cases  
- Check out the command-line tool: `swift run watch /path/to/monitor`