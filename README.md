# AsyncFileMonitor

[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platforms-macOS%2014%2B-blue.svg)](https://github.com/apple/swift-package-manager)
[![Swift Package Manager](https://img.shields.io/badge/Swift%20Package%20Manager-compatible-brightgreen.svg)](https://github.com/apple/swift-package-manager)

Modern async/await Swift Package for monitoring file system events using CoreFoundation's FSEvents API.

AsyncFileMonitor is the modernized successor to RxFileMonitor, providing the same powerful file monitoring capabilities with Swift 6 concurrency support and no external dependencies.

## Features

- **Zero Dependencies**: Pure Swift package with no external frameworks required
- **Modern Async/await**: Uses `AsyncStream` for natural async/await integration
- **Swift 6 Ready**: Full concurrency support with `Sendable` conformance
- **FSEvents Integration**: Efficient file system monitoring using Apple's native FSEvents API
- **Flexible Monitoring**: Monitor single files, directories, or multiple paths
- **Event Filtering**: Rich event information with detailed change flags

## Usage

### Basic File Monitoring with AsyncStream

```swift
import AsyncFileMonitor

// Monitor a directory
let monitor = FolderContentMonitor(url: URL(fileURLWithPath: "/path/to/monitor/"))

// Use async/await to process events
for await event in monitor.events {
    print("File changed: \(event.filename) at \(event.eventPath)")
    print("Change type: \(event.change)")
}
```

### Convenience API

```swift
import AsyncFileMonitor

// Create monitor using convenience method
let monitor = AsyncFileMonitor.monitor(url: URL(fileURLWithPath: "/Users/you/Documents"))

// Process file events
for await event in monitor.events {
    // Filter for file changes only
    guard event.change.contains(.isFile) else { continue }
    
    // Skip system files
    guard event.filename != ".DS_Store" else { continue }
    
    print("Document changed: \(event.filename)")
}
```

### Monitoring Multiple Paths

```swift
let paths = ["/Users/you/Documents", "/Users/you/Desktop"]
let monitor = AsyncFileMonitor.monitor(paths: paths)

for await event in monitor.events {
    print("Change in \(event.eventPath): \(event.change)")
}
```

### Task-based Processing

```swift
let monitor = FolderContentMonitor(url: folderURL)

let monitorTask = Task {
    for await event in monitor.events {
        // Process file events
        await handleFileChange(event)
    }
}

// Stop monitoring
monitorTask.cancel()
```

### Error Handling with ThrowingStream

```swift
let monitor = FolderContentMonitor(url: folderURL)

do {
    for try await event in monitor.throwingEvents {
        // Process events with error handling capability
        print("Event: \(event)")
    }
} catch {
    print("Monitoring error: \(error)")
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
let monitor = FolderContentMonitor(url: url, latency: 0.0)

// 1-second latency - coalesces rapid changes
let monitor = FolderContentMonitor(url: url, latency: 1.0)
```

A latency of 0.0 can produce too much noise when applications make multiple rapid changes to files. Experiment with slightly higher values (e.g., 0.1-1.0 seconds) to reduce noise.

## Understanding File Events

Different applications generate different event patterns:

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

AsyncFileMonitor provides the same core functionality as RxFileMonitor but with modern Swift concurrency:

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

let monitor = FolderContentMonitor(url: folderUrl)

for await event in monitor.events {
    print("File changed: \(event.filename)")
}
```

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