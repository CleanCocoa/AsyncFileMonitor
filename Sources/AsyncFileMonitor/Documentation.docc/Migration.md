# Migrating from RxFileMonitor

Learn how to migrate from RxFileMonitor to AsyncFileMonitor's modern async/await API.

## Overview

AsyncFileMonitor provides the same core functionality as [RxFileMonitor](https://github.com/RxSwiftCommunity/RxFileMonitor/) but with modern Swift concurrency. This guide shows how to update your existing RxFileMonitor code.

## Key Differences

| RxFileMonitor | AsyncFileMonitor |
|---------------|------------------|
| RxSwift Observable | AsyncStream |
| Disposable/DisposeBag | Task cancellation |
| Synchronous callbacks | async/await |
| Manual lifecycle | Automatic lifecycle |

## Basic Migration

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

// Stop monitoring
disposeBag = DisposeBag()
```

### After (AsyncFileMonitor)

**Basic Usage**
```swift
import AsyncFileMonitor

let stream = FolderContentMonitor.makeStream(url: folderUrl)

for await event in stream {
    print("File changed: \(event.filename)")
}

// Monitoring stops automatically when loop exits
```

**Task-based**
```swift
import AsyncFileMonitor

let monitorTask = Task {
    let stream = FolderContentMonitor.makeStream(url: folderUrl)
    
    for await event in stream {
        print("File changed: \(event.filename)")
    }
}

// Stop monitoring
monitorTask.cancel()
```

## Filtering and Operators

### RxFileMonitor Filtering

```swift
monitor.rx.folderContentChange
    .filter { $0.change.contains(.isFile) }
    .filter { $0.change.contains(.modified) }
    .subscribe(onNext: { event in
        processFile(event)
    })
    .disposed(by: disposeBag)
```

### AsyncFileMonitor Filtering

```swift
let stream = FolderContentMonitor.makeStream(url: folderUrl)

for await event in stream 
where event.change.contains(.isFile) && event.change.contains(.modified) {
    await processFile(event)
}
```

## Multiple Streams

### RxFileMonitor

```swift
// UI updates
monitor.rx.folderContentChange
    .observeOn(MainScheduler.instance)
    .subscribe(onNext: { event in
        updateUI(for: event)
    })
    .disposed(by: disposeBag)

// Background processing  
monitor.rx.folderContentChange
    .observeOn(backgroundScheduler)
    .subscribe(onNext: { event in
        processInBackground(event)
    })
    .disposed(by: disposeBag)
```

### AsyncFileMonitor

```swift
// Create independent streams
let uiStream = FolderContentMonitor.makeStream(url: folderUrl)
let backgroundStream = FolderContentMonitor.makeStream(url: folderUrl)

// UI updates
Task { @MainActor in
    for await event in uiStream {
        updateUI(for: event)
    }
}

// Background processing
Task.detached {
    for await event in backgroundStream {
        await processInBackground(event)
    }
}
```

## Error Handling

### RxFileMonitor

```swift
monitor.rx.folderContentChange
    .subscribe(
        onNext: { event in
            processEvent(event)
        },
        onError: { error in
            print("Monitor error: \(error)")
        }
    )
    .disposed(by: disposeBag)
```

### AsyncFileMonitor

```swift
do {
    let stream = FolderContentMonitor.makeStream(url: folderUrl)
    
    for await event in stream {
        await processEvent(event)
    }
} catch {
    print("Monitor error: \(error)")
}
```

## Combining Multiple Monitors

### RxFileMonitor

```swift
let documentsMonitor = FolderContentMonitor(url: documentsUrl)
let desktopMonitor = FolderContentMonitor(url: desktopUrl)

Observable.merge([
    documentsMonitor.rx.folderContentChange,
    desktopMonitor.rx.folderContentChange
])
.subscribe(onNext: { event in
    print("Change in: \(event.eventPath)")
})
.disposed(by: disposeBag)
```

### AsyncFileMonitor

```swift
// Option 1: Monitor multiple paths with single stream
let stream = FolderContentMonitor.makeStream(paths: [
    documentsUrl.path,
    desktopUrl.path
])

for await event in stream {
    print("Change in: \(event.eventPath)")
}

// Option 2: Merge streams using TaskGroup
await withTaskGroup(of: Void.self) { group in
    group.addTask {
        let stream = FolderContentMonitor.makeStream(url: documentsUrl)
        for await event in stream {
            await handleEvent(event)
        }
    }
    
    group.addTask {
        let stream = FolderContentMonitor.makeStream(url: desktopUrl)
        for await event in stream {
            await handleEvent(event)
        }
    }
}
```

## Advanced Patterns

### Debouncing (RxFileMonitor)

```swift
monitor.rx.folderContentChange
    .debounce(.milliseconds(500), scheduler: MainScheduler.instance)
    .subscribe(onNext: { event in
        processDebounced(event)
    })
    .disposed(by: disposeBag)
```

### Debouncing (AsyncFileMonitor)

```swift
let stream = FolderContentMonitor.makeStream(url: folderUrl, latency: 0.5)

for await event in stream {
    // Events are automatically coalesced by FSEvents
    await processDebounced(event)
}

// For custom debouncing:
var lastEventTime = Date()
let debounceInterval: TimeInterval = 0.5

for await event in stream {
    let now = Date()
    if now.timeIntervalSince(lastEventTime) >= debounceInterval {
        await processDebounced(event)
        lastEventTime = now
    }
}
```

## Benefits of Migration

### Simplified Code
- No more disposables or dispose bags
- Natural async/await integration
- Automatic resource management

### Better Performance
- Native Swift concurrency
- Reduced memory overhead
- More efficient resource sharing

### Modern Swift Features
- Full Swift 6 concurrency support
- Sendable conformance  
- Actor-based thread safety

## Common Pitfalls

### 1. Async Context Required
AsyncFileMonitor requires an async context:

```swift
// ❌ Won't compile
func setupMonitoring() {
    let stream = FolderContentMonitor.makeStream(url: url)
    // Cannot use 'for await' in non-async function
}

// ✅ Correct
func setupMonitoring() async {
    let stream = FolderContentMonitor.makeStream(url: url)
    for await event in stream {
        // Handle event
    }
}
```

### 2. Task Management
Remember to manage long-running tasks:

```swift
// ❌ Task may leak
Task {
    let stream = FolderContentMonitor.makeStream(url: url)
    for await event in stream { /* ... */ }
}

// ✅ Proper task management
let monitorTask = Task {
    let stream = FolderContentMonitor.makeStream(url: url)  
    for await event in stream { /* ... */ }
}

// Clean up when done
defer { monitorTask.cancel() }
```

### 3. Actor Isolation
Be aware of actor isolation when updating UI:

```swift
// ❌ May not be on main actor
for await event in stream {
    updateUI(for: event)  // Potential concurrency issue
}

// ✅ Ensure main actor for UI updates
for await event in stream {
    await MainActor.run {
        updateUI(for: event)
    }
}
```