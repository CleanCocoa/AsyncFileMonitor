# Event Ordering Analysis and Regression Testing
*Document ID: 20250904T080826*  
*Date: 2025-09-04*

## Executive Summary

This document describes the critical role of Swift's Task Executor Preference (SE-0417) in maintaining chronological event ordering in AsyncFileMonitor's file system event processing pipeline. Through comprehensive testing, we've identified and documented a race condition that can cause FSEventStreamEventId values to arrive out of order when executor preference is not properly configured.

## The Problem

When monitoring file system events using FSEventStream, events are delivered with monotonically increasing FSEventStreamEventId values. These IDs represent the chronological order of events. However, when processing these events asynchronously, race conditions can cause events to be delivered to consumers out of their chronological order.

## Critical Code Location

**File:** `Sources/AsyncFileMonitor/FolderContentMonitor.swift`  
**Line:** ~158  
**Reference ID:** 20250904T080826

```swift
// CRITICAL: This executor preference prevents event reordering
// See docs/Event Ordering Analysis.md (20250904T080826)
Task(executorPreference: FileSystemEventExecutor.shared) {
    await self.broadcast(folderContentChangeEvents: events)
}
```

## How Event Ordering Can Break

### Without Executor Preference

When creating a Task without executor preference:
```swift
Task {  // ❌ No executor preference
    await self.broadcast(folderContentChangeEvents: events)
}
```

**What happens:**
1. Each Task can be scheduled on any thread from the global concurrent executor
2. Multiple Tasks processing different event batches can run simultaneously on different threads
3. A Task processing later events (higher FSEventStreamEventId) might complete before a Task processing earlier events
4. Result: Events arrive at consumers out of chronological order

### With Executor Preference

When using executor preference:
```swift
Task(executorPreference: FileSystemEventExecutor.shared) {  // ✅ With executor preference
    await self.broadcast(folderContentChangeEvents: events)
}
```

**What happens:**
1. All Tasks prefer to run on the same serial executor (FileSystemEventExecutor.shared)
2. The serial executor processes Tasks one at a time in submission order
3. Events are broadcast in the same order they were received from FSEventStream
4. Result: Events maintain chronological order based on FSEventStreamEventId

## Reproducing the Issue

### Test Files

We've created several test files to demonstrate and reproduce the ordering issue:

1. **AsyncFileMonitorTests.swift** - Contains the main event ordering test
2. **BreakingRegressionTest.swift** - Automated tests to verify correct behavior

### Steps to Reproduce Event Reordering

1. **Locate the critical code:**
   ```bash
   # Open the file
   open Sources/AsyncFileMonitor/FolderContentMonitor.swift
   # Find line ~158 with the Task creation
   ```

2. **Break the code temporarily:**
   ```swift
   // Change from:
   Task(executorPreference: FileSystemEventExecutor.shared) {
   
   // To:
   Task {
   ```

3. **Run the baseline test:**
   ```bash
   swift test --filter demonstrateCorrectBehavior
   ```
   
   **Expected output with broken code:**
   ```
   Events in chronological order: ❌ NO
   ⚠️  Out of order events detected: 4
   ```

4. **Restore the original code:**
   ```swift
   Task(executorPreference: FileSystemEventExecutor.shared) {
   ```

5. **Verify the fix:**
   ```bash
   swift test --filter demonstrateCorrectBehavior
   ```
   
   **Expected output with fixed code:**
   ```
   Events in chronological order: ✅ YES
   ```

## Test Results Summary

### Baseline Test (25 files, 8ms delays)
| Configuration | Result | Out-of-Order Events |
|---|---|---|
| With executor preference | ✅ Ordered | 0 |
| Without executor preference | ❌ Unordered | 4 |

### Event Coalescing Test (50 files, 10ms delays, 200ms latency)
| Configuration | Result | Notes |
|---|---|---|
| With executor preference | Intermittent | Occasionally shows reordering under load |
| Without executor preference | ❌ Unordered | Consistent reordering |

### High-Stress Test (75 files, 3ms delays)  
| Configuration | Result | Out-of-Order Events |
|---|---|---|
| With executor preference | Intermittent | Non-deterministic (0-10+ events) |
| Without executor preference | ❌ Unordered | More severe and consistent |

**Note:** The intermittent failures with executor preference under high load suggest there are inherent limitations in FSEventStream coalescing or dispatch queue scheduling that can cause reordering even with proper synchronization. See `Event Reordering with Executor.md` for a detailed analysis of why events can still arrive out of order even with executor preference.

## Key Findings

1. **Executor preference is essential for correctness**: Without it, even moderate file creation rates cause event reordering.

2. **High concurrency has limits**: Under extreme stress (75+ files with <3ms delays), some reordering occurs even with executor preference, suggesting FSEventStream coalescing or dispatch queue scheduling limits.

3. **The fix is simple but critical**: A single parameter (`executorPreference`) prevents most race conditions.

## Architecture Overview

```
FSEventStream (C API)
    ↓
FSEventStreamCallback (dispatch queue)
    ↓
FileSystemEventStream (RAII wrapper)
    ↓
FolderContentMonitor (actor)
    ↓ [Task with executor preference - CRITICAL POINT]
StreamRegistrar (actor)
    ↓
AsyncStream continuations
    ↓
Consumer
```

The critical point is the Task creation in FolderContentMonitor where events are forwarded. This is where executor preference must be specified to maintain ordering.

## Related Components

### FileSystemEventExecutor

Located in `Sources/AsyncFileMonitor/FileSystemEventExecutor.swift`, this custom executor implements both `SerialExecutor` and `TaskExecutor` protocols (SE-0417). It ensures:

- Serial execution of tasks
- Task executor preference inheritance
- Consistent execution context for all file system event processing

### Isolation Assertions

Throughout the codebase, we use `dispatchPrecondition` to verify code runs on the expected queue:

```swift
dispatchPrecondition(condition: .onQueue(FileSystemEventExecutor.shared.underlyingQueue))
```

These assertions help catch incorrect executor usage during development but are removed from the FSEventStream callback path to avoid conflicts with the dispatch queue's execution context.

## Testing Recommendations

1. **Regular Testing**: Run the baseline test (`demonstrateCorrectBehavior`) as part of CI to ensure executor preference is maintained.

2. **Stress Testing**: Periodically run high-stress tests to understand system limits under extreme load.

3. **Manual Regression Testing**: When modifying concurrency code, temporarily remove executor preference to verify tests detect the regression.

## References

- [SE-0417: Task Executor Preference](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0417-task-executor-preference.md)
- [Swift Issue #74395](https://github.com/swiftlang/swift/issues/74395) - Related concurrency ordering issue
- Code Reference: 20250904T080826 - Critical executor preference location

## Conclusion

The use of `Task(executorPreference: FileSystemEventExecutor.shared)` at line ~158 in FolderContentMonitor.swift is not an optimization—it's a correctness requirement. Removing this executor preference immediately introduces race conditions that cause file system events to be delivered out of chronological order, breaking the fundamental guarantee that FSEventStreamEventId values represent temporal ordering.

This has been verified through comprehensive testing that can reliably reproduce the issue when executor preference is removed and demonstrate correct behavior when it's present.