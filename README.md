# AsyncFileMonitor

[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platforms-macOS%2014%2B-blue.svg)](https://github.com/apple/swift-package-manager)
[![Swift Package Manager](https://img.shields.io/badge/Swift%20Package%20Manager-compatible-brightgreen.svg)](https://github.com/apple/swift-package-manager)

Modern async/await Swift Package for monitoring file system events using CoreFoundation's FSEvents API.

AsyncFileMonitor is the modernized successor to RxFileMonitor, providing the same powerful file monitoring capabilities with Swift 6 concurrency support and no external dependencies.

## Features

- **Modern Async/await**: Uses `AsyncStream` for natural async/await integration
- **Swift 6 Ready**: Full concurrency support with `Sendable` conformance
- **FSEvents Integration**: Efficient file system monitoring using Apple's native FSEvents API
- **Flexible Monitoring**: Monitor single files, directories, or multiple paths
- **Event Filtering**: Rich event information with detailed change flags

## Usage

### Direct AsyncStream API

```swift
import AsyncFileMonitor

// Monitor a directory using the convenience API
let eventStream = AsyncFileMonitor.monitor(url: URL(fileURLWithPath: "/path/to/monitor/"))

// Use async/await to process events
for await event in eventStream {
    print("File changed: \(event.filename) at \(event.eventPath)")
    print("Change type: \(event.change)")
}
```

### Alternative API (Direct from FolderContentMonitor)

```swift
import AsyncFileMonitor

// Create a stream directly from FolderContentMonitor
let eventStream = FolderContentMonitor.monitor(
    url: URL(fileURLWithPath: "/Users/you/Documents"),
    latency: 0.5  // Coalesce rapid changes
)

// Process file events
for await event in eventStream {
    // Filter for file changes only
    guard event.change.contains(.isFile) else { continue }
    
    // Skip system files
    guard event.filename != ".DS_Store" else { continue }
    
    print("Document changed: \(event.filename)")
}
```

### Monitoring Multiple Paths

```swift
let eventStream = AsyncFileMonitor.monitor(paths: [
    "/Users/you/Documents", 
    "/Users/you/Desktop"
])

for await event in eventStream {
    print("Change in \(event.eventPath): \(event.change)")
}
```

### Task-based Processing

```swift
let eventStream = AsyncFileMonitor.monitor(url: folderURL)

let monitorTask = Task {
    for await event in eventStream {
        // Process file events
        await handleFileChange(event)
    }
}

// Stop monitoring
monitorTask.cancel()
```

### Filtering Events

```swift
let eventStream = AsyncFileMonitor.monitor(url: documentsURL)

for await event in eventStream
where event.change.contains(.isFile) && event.change.contains(.modified) {
    await processModifiedFile(event.url)
}
```

### Multiple Concurrent Streams

Each call to `monitor()` creates an independent stream with its own FSEventStream:

```swift
// Create multiple independent streams monitoring the same directory
let uiUpdateStream = AsyncFileMonitor.monitor(url: documentsURL)
let backupStream = AsyncFileMonitor.monitor(url: documentsURL)
let logStream = AsyncFileMonitor.monitor(url: documentsURL)

// Process events differently in each stream
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

## Event Types

The `Change` struct provides detailed information about what changed:

### File Type Flags
- `.isFile` - The item is a regular file
- `.isDirectory` - The item is a directory  
- `.isSymlink` - The item is a symbolic link
- `.isHardlink` - The item is a hard link

### Change Type Flags
- `.created` - Item was created
- `.modified` - Item was modified
- `.removed` - Item was removed
- `.renamed` - Item was renamed/moved

### Metadata Changes
- `.changeOwner` - Ownership changed
- `.finderInfoModified` - Finder info changed
- `.inodeMetaModified` - Inode metadata changed
- `.xattrsModified` - Extended attributes changed

## Latency Configuration

Control event coalescing with the `latency` parameter:

```swift
// No latency - all events reported immediately (can be noisy)
let eventStream = AsyncFileMonitor.monitor(url: url, latency: 0.0)

// 1-second latency - coalesces rapid changes
let eventStream = AsyncFileMonitor.monitor(url: url, latency: 1.0)
```

A latency of 0.0 can produce too much noise when applications make multiple rapid changes to files. Experiment with slightly higher values (e.g., 0.1-1.0 seconds) to reduce noise.

## Understanding File Events

Different applications can generate different event patterns:

### TextEdit (atomic saves):
```
texteditfile.txt changed (isFile, renamed, xattrsModified)
texteditfile.txt changed (isFile, renamed, finderInfoModified, xattrsModified)
texteditfile.txt.sb-56afa5c6-DmdqsL changed (isFile, renamed)
texteditfile.txt changed (isFile, renamed, finderInfoModified, inodeMetaModified, xattrsModified)
texteditfile.txt.sb-56afa5c6-DmdqsL changed (isFile, modified, removed, renamed, changeOwner)
```

### Simple editors (direct writes):
```
file.txt changed (isFile, modified, xattrsModified)
```

## Installation

### Swift Package Manager

Add AsyncFileMonitor to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/AsyncFileMonitor.git", from: "1.0.0")
]
```

Or add it through Xcode:
1. File > Add Package Dependencies
2. Enter the repository URL
3. Select your target

## Requirements

- macOS 14.0+
- Swift 6.0+
- Xcode 16.0+

## Migration from RxFileMonitor

AsyncFileMonitor provides the same core functionality as [RxFileMonitor](https://github.com/RxSwiftCommunity/RxFileMonitor/) but with modern Swift concurrency:

### Before (RxFileMonitor)
```swift
import RxFileMonitor
import RxSwift

let monitor = FolderContentMonitor(url: folderUrl)
let disposeBag = DisposeBag()

monitor.rx.folderContentChange
    .subscribe(onNext: { event in
        print("File changed: \(event.filename)")
    })
    .disposed(by: disposeBag)
```

### After (AsyncFileMonitor)

**Option 1: Direct convenience API**
```swift
import AsyncFileMonitor

let eventStream = AsyncFileMonitor.monitor(url: folderUrl)

for await event in eventStream {
    print("File changed: \(event.filename)")
}
```

**Option 2: Direct from FolderContentMonitor**
```swift
import AsyncFileMonitor

let eventStream = FolderContentMonitor.monitor(url: folderUrl)

for await event in eventStream {
    print("File changed: \(event.filename)")
}
```

## Architecture

AsyncFileMonitor uses a layered architecture for efficient resource sharing and clean separation of concerns:

```
FolderContentMonitor (public API)
    ↓
ManagerRegistry (actor - thread-safe manager coordination)  
    ↓
StreamManager (actor - FSEventStream management)
    ↓
OrderedDictionary<Int, Continuation> (simple continuation storage)
```

### Key Design Benefits

- **Resource Sharing**: Multiple `AsyncStream` instances monitoring the same path share a single `FSEventStream`
- **Automatic Lifecycle**: FSEventStreams start when the first client connects, stop when the last disconnects
- **Thread Safety**: All coordination happens through isolated actors with custom executors
- **Configurable Performance**: Each monitor uses a configurable `DispatchSerialQueue` with specified QoS priority
- **Clean API**: Simple `monitor()` calls return independent `AsyncStream` instances

## Building and Testing

```bash
# Build
make build

# Run tests  
make test

# Format code
make format

# Clean
make clean
```

## License

Copyright (c) 2016 Christian Tietze, RxSwiftCommunity (original RxFileMonitor)  
Copyright (c) 2025 Christian Tietze (AsyncFileMonitor modernization)

Distributed under The MIT License. See LICENSE file for details.
