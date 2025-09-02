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

### Advanced Configuration

```swift
import AsyncFileMonitor

// Create a stream with custom configuration
let eventStream = FolderContentMonitor.makeStream(
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
let eventStream = FolderContentMonitor.makeStream(paths: [
    "/Users/you/Documents", 
    "/Users/you/Desktop"
])

for await event in eventStream {
    print("Change in \(event.eventPath): \(event.change)")
}
```

### Task-based Processing

```swift
let eventStream = FolderContentMonitor.makeStream(url: folderURL)

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
let eventStream = FolderContentMonitor.makeStream(url: documentsURL)

for await event in eventStream
where event.change.contains(.isFile) && event.change.contains(.modified) {
    await processModifiedFile(event.url)
}
```

### Multiple Concurrent Streams

Each call to `makeStream()` creates an independent stream with its own FSEventStream:

```swift
// Create multiple independent streams monitoring the same directory
let uiUpdateStream = FolderContentMonitor.makeStream(url: documentsURL)
let backupStream = FolderContentMonitor.makeStream(url: documentsURL)
let logStream = FolderContentMonitor.makeStream(url: documentsURL)

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
let eventStream = FolderContentMonitor.makeStream(url: url, latency: 0.0)

// 1-second latency - coalesces rapid changes
let eventStream = FolderContentMonitor.makeStream(url: url, latency: 1.0)
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
```swift
import AsyncFileMonitor

let eventStream = FolderContentMonitor.makeStream(url: folderUrl)

for await event in eventStream {
    print("File changed: \(event.filename)")
}
```

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

- **Resource Sharing**: Multiple `AsyncStream` instances can share a single FSEventStream
- **Automatic Lifecycle**: FSEventStreams start when the first client connects, stop when the last disconnects
- **Thread Safety**: All coordination happens through isolated actors with custom executors
- **Configurable Performance**: Each monitor uses a configurable `DispatchSerialQueue` with specified QoS priority
- **Clean API**: Simple `makeStream()` calls return independent `AsyncStream` instances

## Command Line Tool

AsyncFileMonitor includes a built-in CLI tool for monitoring file changes:

```bash
# Monitor a single directory
swift run watch /Users/username/Documents

# Monitor multiple directories
swift run watch /path/to/folder1 /path/to/folder2

# Show usage help
swift run watch
```

### CLI Features
- **Real-time Monitoring**: Live display of file system events with timestamps
- **Detailed Output**: Shows event path, change types, and event IDs
- **Multi-path Support**: Monitor multiple directories simultaneously
- **Path Validation**: Validates paths exist before starting monitoring
- **Debug Logging**: Enables AsyncFileMonitor's internal logging for troubleshooting

### Example Output
```
🎯 Starting AsyncFileMonitor CLI
📁 Monitoring paths:
   • /Users/username/Documents
📡 Press Ctrl+C to stop monitoring

[14:23:15.123] 📄 /Users/username/Documents/test.txt
                🔄 isFile, modified
                🆔 Event ID: 12345678

[14:23:15.456] 📄 /Users/username/Documents/newfile.txt
                🔄 isFile, created
                🆔 Event ID: 12345679
```

## Building and Testing

```bash
# Build
make build

# Build and run CLI tool
swift run watch /path/to/monitor

# Generate documentation
make docs

# Preview documentation in browser
make docs-preview

# Generate static documentation website
make docs-static

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
