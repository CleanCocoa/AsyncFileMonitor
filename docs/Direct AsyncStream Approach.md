# Direct AsyncStream Approach for File System Monitoring

**Reference**: 20250905T073442  
**Implementation**: `Tests/RaceConditionTests/4_DirectAsyncStream.swift`

## Overview

This document describes a direct AsyncStream.Continuation approach that bypasses Swift actors entirely, using a custom `MulticastAsyncStream` for event distribution. Surprisingly, this approach demonstrates **superior ordering guarantees** compared to the actor/executor coordination approach documented in [Event Reordering with Executor.md](Event%20Reordering%20with%20Executor.md).

## Architecture

### Core Components

1. **`MulticastAsyncStream<T>`** - Thread-safe multicast broadcaster using:
   - `OrderedDictionary` for preserving subscriber registration order
   - Swift 6 `Mutex` for safe synchronization
   - Direct `AsyncStream.Continuation` management

2. **`DirectStreamFileMonitor`** - Simple file monitor that:
   - Creates a single FSEventStream
   - Forwards events directly to MulticastAsyncStream
   - No actor isolation or Task scheduling

3. **Direct FSEventStream Callback** - C callback that:
   - Extracts MulticastAsyncStream from context
   - Yields events directly to all continuations
   - No Swift concurrency task creation

## Why This Approach is Superior

### 1. Eliminates Swift Concurrency Scheduling

The actor/executor approach, despite custom executors and Task preferences, still relies on Swift's cooperative scheduling:

```swift
// Actor/Executor approach - still subject to scheduling
Task(executorPreference: FileSystemEventExecutor.shared) {
    await self.broadcast(folderContentChangeEvents: events)
}
```

The direct approach bypasses this entirely:

```swift
// Direct approach - no Task scheduling
multicastStream.send(event)  // Called directly from C callback
```

### 2. Preserves FSEventStream Ordering

FSEventStream delivers events in chronological order on its callback queue. The direct approach maintains this ordering by:

- **No context switches**: Events flow directly from C callback to AsyncStream continuations
- **No Task boundaries**: No opportunity for Swift concurrency to reorder events
- **Synchronous processing**: All subscribers receive events in the same order, immediately

### 3. Ordered Subscriber Management

Unlike `Dictionary`-based approaches, `MulticastAsyncStream` uses `OrderedDictionary`:

```swift
private let continuations: Mutex<OrderedDictionary<UUID, AsyncStream<T>.Continuation>>
```

This ensures that when events are broadcast, all subscribers receive them in their registration order, providing deterministic behavior.

### 4. Modern Swift 6 Synchronization

Uses Swift 6's `Mutex` instead of manual `os_unfair_lock`:

```swift
// Safe, type-checked synchronization
continuations.withLock { dict in
    dict[id] = continuation
}
```

Benefits:
- **Type safety**: Mutex protects specific data types
- **Automatic lock management**: `withLock` ensures proper cleanup
- **Sendable conformance**: Proper Swift 6 concurrency integration
- **Cross-platform**: Works beyond just Darwin platforms

## Performance Characteristics

### Stress Test Results

The direct approach **consistently passes** high-stress tests (100 files, 1ms intervals) that cause intermittent failures in the actor/executor approach:

- **Actor/Executor**: Requires `withKnownIssue` for high-stress scenarios
- **Direct AsyncStream**: Maintains perfect ordering even under extreme load

### Why It's More Reliable

1. **Fewer abstraction layers**: C callback → Mutex → AsyncStream continuations
2. **No async/await boundaries**: Events never cross Task suspension points
3. **Deterministic execution**: No scheduler-dependent timing variations
4. **Thread-local processing**: Events processed immediately on FSEventStream's queue

## Implementation Details

### Thread Safety Model

```swift
public final class MulticastAsyncStream<T>: Sendable {
    private let continuations: Mutex<OrderedDictionary<UUID, AsyncStream<T>.Continuation>>
    
    public func send(_ value: T) where T: Sendable {
        let currentContinuations = continuations.withLock { dict in
            Array(dict.values)  // Snapshot for safe iteration
        }
        
        for c in currentContinuations {
            c.yield(value)  // Direct yield to each continuation
        }
    }
}
```

### Event Flow

```
FSEventStream (C API)
       ↓
C Callback Function
       ↓
MulticastAsyncStream.send()
       ↓
AsyncStream.Continuation.yield()
       ↓
Multiple AsyncStream consumers
```

## Trade-offs

### Advantages
- ✅ Perfect ordering guarantees under all tested conditions
- ✅ Lower latency (no Task scheduling overhead)
- ✅ More predictable performance
- ✅ Simpler debugging (fewer abstraction layers)
- ✅ Modern Swift 6 synchronization primitives

### Limitations
- ❌ Bypasses Swift concurrency best practices
- ❌ Less integration with structured concurrency
- ❌ Manual resource management (no actor lifecycle)
- ❌ C callback context management required

## Comparison with Actor/Executor Approach

| Aspect | Actor/Executor | Direct AsyncStream |
|--------|----------------|-------------------|
| **Ordering under load** | Intermittent failures | Consistently reliable |
| **Swift concurrency integration** | Excellent | Limited |
| **Code complexity** | Higher | Lower |
| **Resource management** | Automatic | Manual |
| **Performance predictability** | Variable | Consistent |
| **Debugging difficulty** | High | Medium |

## When to Use This Approach

The direct AsyncStream approach is particularly valuable when:

1. **Ordering is critical**: Events must maintain strict chronological order
2. **High throughput**: System processes many rapid events
3. **Low latency requirements**: Minimizing event processing delay is important
4. **Predictable performance**: Consistent behavior is preferred over sophisticated abstractions

## Future Considerations

While this approach demonstrates superior ordering characteristics, the Swift concurrency model continues to evolve. Future Swift versions may address the scheduling limitations that make this direct approach necessary.

Until then, this implementation serves as both a working solution and educational example of when bypassing high-level abstractions can yield better results for specific requirements.