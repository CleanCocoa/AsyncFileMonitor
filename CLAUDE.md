# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Core Commands
- `make build` - Build the Swift package
- `make test` - Run tests with filtered output (uses custom script to reduce noise)
- `make format` - Format Swift code in Sources/ and Tests/ directories
- `make clean` - Clean build artifacts

### CLI Tool Commands
- `swift run watch <path>` - Monitor file system changes in real-time
- `swift run watch <path1> <path2>` - Monitor multiple paths simultaneously
- `swift run watch` - Show CLI usage help

## Project Architecture

AsyncFileMonitor is a modern Swift 6 package that provides async/await file system monitoring using Apple's FSEvents API. The architecture is built around these key components:

### Core API Structure
- **FolderContentMonitor** (`FolderContentMonitor.swift`) - Caseless enum namespacing the static `makeStream` factories
- **FolderContentChangeEvent** (`FolderContentChangeEvent.swift`) - Event data structure representing file system changes
- **Change** (`Change.swift`) - OptionSet over the item flags of FSEventStreamEventFlags
- **StreamCondition** (`StreamCondition.swift`) - OptionSet over the stream flags: dropped events, invalidated state, sentinels
- **FileSystemEventStream** (`FileSystemEventStream.swift`) - Non-copyable RAII wrapper owning one FSEventStream

### Key Design Patterns
- **AsyncStream-based**: All monitoring returns `AsyncStream<FolderContentChangeEvent>` for natural async/await integration
- **RAII Resource Management**: Each call to `makeStream()` creates its own `FileSystemEventStream`, released when the returned stream terminates
- **Zero Dependencies**: Pure Swift implementation using only Foundation and CoreFoundation
- **Independent Streams**: Multiple concurrent streams can monitor the same path independently, each with their own FSEventStream

### FSEventStream Integration
The non-copyable `FileSystemEventStream` manages FSEventStream lifecycle:
- Creates FSEventStream with file-level events enabled (`kFSEventStreamCreateFlagFileEvents`)
- Uses a dedicated `.userInteractive` dispatch queue for event delivery
- Properly handles stream creation, start, stop, invalidation, and release
- Converts raw FSEventStreamEventFlags to typed `Change` and `StreamCondition` options
- Delivers one FSEvents callback's worth of events per handler invocation

### Testing Framework
Uses Swift Testing (not XCTest):
- Tests are written with `@Test` attributes 
- Async tests use `confirmation()` helper for event verification
- TestHelpers.swift provides `matches()` extension for event filtering in tests
- Integration tests create temporary directories and verify actual file system events

## File System Event Handling

The library handles complex FSEvents patterns including:
- **Atomic Saves**: Applications like TextEdit create temporary files and rename them, generating multiple events
- **Metadata Changes**: Tracks extended attributes, Finder info, inode metadata changes
- **File Type Detection**: Distinguishes between files, directories, symlinks, hardlinks
- **Event Coalescing**: Latency parameter allows grouping rapid successive changes

## Package Configuration

- **Minimum Platform**: macOS 15.0+ (see `Package.swift`)
- **Swift Version**: 6.0+
- **Package Type**: Library with CLI tool
- **Dependencies**: none for the library target; swift-collections is used by RaceConditionTests
- **Targets**:
  - `AsyncFileMonitor` - Main library target
  - `watch` - CLI tool executable (internal, not exposed as product)
  - `AsyncFileMonitorTests` - Test suite

## CLI Tool Implementation

The `watch` CLI tool (`Sources/watch/Watch.swift`) provides a practical demonstration of AsyncFileMonitor usage:
- **Real-time Monitoring**: Uses AsyncFileMonitor.monitor() to watch file changes
- **Logger Integration**: Enables AsyncFileMonitorLogger for debugging FSEvent activity
- **Multi-path Support**: Can monitor multiple directories simultaneously
- **User-friendly Output**: Shows timestamps, file paths, change types, and event IDs
- **Path Validation**: Verifies paths exist before starting monitoring
- **Graceful Handling**: Provides clear usage messages and error handling
