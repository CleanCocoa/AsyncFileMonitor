# Understanding File System Events

Learn about the different types of file system events and how to interpret them.

## Overview

AsyncFileMonitor reports detailed information about file system changes through the ``Change`` structure. Understanding these events helps you build robust file monitoring applications.

## Event Structure

Each file system change generates a ``FolderContentChangeEvent`` with:

- **eventID**: Unique FSEvent identifier
- **eventPath**: Full path to the changed item
- **change**: ``Change`` flags describing what happened

```swift
for await event in stream {
    print("Event ID: \(event.eventID)")
    print("Path: \(event.eventPath)")  
    print("Filename: \(event.filename)")
    print("Changes: \(event.change)")
}
```

## File Type Identification

The ``Change`` structure includes flags to identify the type of item that changed:

```swift
for await event in stream {
    if event.change.contains(.isFile) {
        print("Regular file changed: \(event.filename)")
    }
    
    if event.change.contains(.isDirectory) {
        print("Directory changed: \(event.filename)")
    }
    
    if event.change.contains(.isSymlink) {
        print("Symbolic link changed: \(event.filename)")
    }
    
    if event.change.contains(.isHardlink) {
        print("Hard link changed: \(event.filename)")
    }
}
```

## Change Type Detection

Different types of operations generate specific change flags:

### File Operations

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
    
    if event.change.contains(.renamed) {
        print("File renamed/moved: \(event.filename)")
    }
}
```

### Metadata Changes

File system metadata can change without modifying file contents:

```swift
for await event in stream {
    if event.change.contains(.changeOwner) {
        print("Ownership changed: \(event.filename)")
    }
    
    if event.change.contains(.finderInfoModified) {
        print("Finder info changed: \(event.filename)")
    }
    
    if event.change.contains(.inodeMetaModified) {
        print("Inode metadata changed: \(event.filename)")
    }
    
    if event.change.contains(.xattrsModified) {
        print("Extended attributes changed: \(event.filename)")
    }
}
```

## Application-Specific Event Patterns

Different applications generate distinct event patterns when saving files:

### TextEdit (Atomic Saves)

TextEdit uses atomic saves, creating temporary files and renaming them:

```
texteditfile.txt changed (isFile, renamed, xattrsModified)
texteditfile.txt changed (isFile, renamed, finderInfoModified, xattrsModified)
texteditfile.txt.sb-56afa5c6-DmdqsL changed (isFile, renamed)
texteditfile.txt changed (isFile, renamed, finderInfoModified, inodeMetaModified, xattrsModified)
texteditfile.txt.sb-56afa5c6-DmdqsL changed (isFile, modified, removed, renamed, changeOwner)
```

### Simple Editors (Direct Writes)

Applications that write directly to files generate simpler patterns:

```
file.txt changed (isFile, modified, xattrsModified)
```

### Xcode (Complex Build Operations)

Development tools can generate many rapid events:

```
main.swift changed (isFile, modified, xattrsModified)
.build/ changed (isDirectory, created)
.build/debug/ changed (isDirectory, created)
main.o changed (isFile, created, xattrsModified)
main changed (isFile, created, xattrsModified)
```

## Filtering Strategies

### Focus on User Files

Skip system and temporary files:

```swift
for await event in stream {
    let filename = event.filename
    
    // Skip hidden files and system files
    guard !filename.hasPrefix(".") else { continue }
    
    // Skip common temporary file patterns
    guard !filename.contains("~") else { continue }
    guard !filename.hasSuffix(".tmp") else { continue }
    
    // Process user files
    await processUserFile(event)
}
```

### Monitor Specific File Types

Filter for specific file extensions:

```swift
let documentExtensions = Set(["txt", "md", "pdf", "doc", "docx"])

for await event in stream where event.change.contains(.isFile) {
    let pathExtension = event.url.pathExtension.lowercased()
    
    if documentExtensions.contains(pathExtension) {
        await processDocument(event)
    }
}
```

### Track Content Modifications Only

Focus on actual content changes, ignoring metadata:

```swift
for await event in stream {
    // Only process substantial changes
    if event.change.contains(.created) || 
       event.change.contains(.modified) || 
       event.change.contains(.removed) {
        await processContentChange(event)
    }
    
    // Skip pure metadata changes
    if event.change.isSubset(of: [.finderInfoModified, .xattrsModified]) {
        continue
    }
}
```

## Event Coalescing

Use the `latency` parameter to reduce event noise:

```swift
// High-frequency monitoring (noisy)
let stream = FolderContentMonitor.makeStream(url: url, latency: 0.0)

// Coalesced monitoring (cleaner)
let stream = FolderContentMonitor.makeStream(url: url, latency: 0.5)
```

Higher latency values reduce the number of events but increase the delay between the actual change and notification.

## Debugging Events

Log events to understand patterns in your application:

```swift
let stream = FolderContentMonitor.makeStream(url: url)

for await event in stream {
    print("📁 \(event.eventPath)")
    print("🔄 \(event.change)")
    print("🆔 \(event.eventID)")
    print("---")
}
```

## Best Practices

### 1. Filter Early and Often
Apply filters as early as possible to reduce processing overhead:

```swift
for await event in stream 
where event.change.contains(.isFile) && event.change.contains(.modified) {
    // Only process file modifications
    await handleFileModification(event)
}
```

### 2. Batch Related Events
Group related events when possible:

```swift
var pendingEvents: [FolderContentChangeEvent] = []

for await event in stream {
    pendingEvents.append(event)
    
    // Process batch after brief delay
    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
    
    if !pendingEvents.isEmpty {
        await processBatch(pendingEvents)
        pendingEvents.removeAll()
    }
}
```

### 3. Handle Edge Cases
Be prepared for unusual event combinations:

```swift
for await event in stream {
    // File might be both created and removed in rapid succession
    if event.change.contains(.created) && event.change.contains(.removed) {
        // Temporary file that was cleaned up quickly
        continue
    }
    
    // Handle normal cases
    await processEvent(event)
}
```

## Performance Considerations

- **Latency**: Higher values reduce event frequency but increase delay
- **Filtering**: Apply filters early to reduce processing overhead  
- **Batching**: Group related events to reduce system calls
- **Async Processing**: Use async/await to avoid blocking the event stream