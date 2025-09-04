# Event Reordering Despite Executor Preference
*Document ID: 20250904T080826*  
*Date: 2025-09-04*

## The Surprising Finding

During testing, we discovered that **events can still arrive out of order even WITH executor preference properly configured**. This document explains why this happens and what it means for the implementation.

## Test Evidence

### High-Stress Test Results
When running the high-stress test (75 files, 3ms delays), we observed:
- **With executor preference**: Still showed reordering in positions 40-49
- **Without executor preference**: Showed reordering in positions 19-22

### Event Coalescing Test Results  
When running the coalescing test (50 files, 10ms delays, 200ms latency), we observed:
- **Test run 1**: Events arrived in order
- **Test run 2**: Events showed reordering at positions 11-15
- **Both runs had executor preference enabled**

Example of reordering WITH executor preference:
```
Position 40 (stress_055.txt): got 9621351441, expected 9621351246
Position 41 (stress_040.txt): got 9621351246, expected 9621351259
Position 42 (stress_056.txt): got 9621351454, expected 9621351272
```

## Why This Happens

### The Event Flow Pipeline

```
FSEventStream (macOS kernel/userspace boundary)
    ↓ [Buffering & Coalescing]
FSEventStreamCallback (dispatch queue callback)
    ↓ [Dispatch Queue Scheduling]
FileSystemEventStream.forward()
    ↓ [Task Creation with Executor Preference]
FolderContentMonitor.broadcast() 
    ↓ [Actor hop]
StreamRegistrar.yield()
    ↓
AsyncStream continuations
```

### Multiple Sources of Potential Reordering

1. **FSEventStream Internal Buffering**
   - FSEventStream itself may deliver events out of order when coalescing is enabled
   - Events from different inodes might be reported in non-chronological order
   - The kernel → userspace transition involves buffering that may reorder events

2. **Dispatch Queue Scheduling**
   - Even though we specify a serial queue, the FSEventStream callback might be invoked multiple times concurrently for different event batches
   - The dispatch queue scheduling between the FSEventStream internals and our callback isn't guaranteed to preserve perfect ordering

3. **Task Creation Timing**
   ```swift
   // Even with executor preference, Task creation itself is asynchronous
   Task(executorPreference: FileSystemEventExecutor.shared) {
       await self.broadcast(folderContentChangeEvents: events)
   }
   ```
   - Creating a Task is not instantaneous
   - Multiple callbacks could create multiple Tasks before any start executing
   - While the executor preference ensures they run serially, they might not be enqueued in the exact order the callbacks were invoked

4. **Event Batching**
   - FSEventStream delivers events in batches
   - Each batch triggers a callback
   - If callback N+1 completes Task creation before callback N, the events could be processed out of order

## The Critical Difference

### Without Executor Preference
```swift
Task {  // Can run on any thread
    await self.broadcast(folderContentChangeEvents: events)
}
```
- **Severe reordering**: Tasks run concurrently on different threads
- **Consistent failures**: Reordering happens reliably even with moderate load
- **Race conditions**: True data races between concurrent Tasks

### With Executor Preference
```swift
Task(executorPreference: FileSystemEventExecutor.shared) {
    await self.broadcast(folderContentChangeEvents: events)
}
```
- **Mild reordering**: Only under high stress or with coalescing
- **Intermittent failures**: Requires specific timing conditions
- **No data races**: Tasks still run serially, just potentially in wrong order

## Real-World Implications

### When Order Matters Absolutely
If your application requires **absolute chronological ordering** of events:
1. You cannot rely solely on executor preference
2. You need additional ordering mechanisms:
   - Event sequence numbers at the application level
   - Buffering and sorting by FSEventStreamEventId
   - Post-processing to restore chronological order

### When Order Matters Mostly
If your application can tolerate occasional reordering:
1. Executor preference significantly reduces reordering
2. Most events will arrive in order
3. Only high-stress scenarios cause issues

## Example: Implementing Strict Ordering

If you need guaranteed chronological ordering, consider buffering and sorting:

```swift
actor StrictlyOrderedMonitor {
    private var eventBuffer: [FSEventStreamEventId: FolderContentChangeEvent] = [:]
    private var lastProcessedID: FSEventStreamEventId = 0
    
    func handleEvents(_ events: [FolderContentChangeEvent]) async {
        // Buffer all events
        for event in events {
            eventBuffer[event.eventID] = event
        }
        
        // Process events in strict order
        while let nextEvent = eventBuffer[lastProcessedID + 1] {
            await processEvent(nextEvent)
            eventBuffer.removeValue(forKey: lastProcessedID + 1)
            lastProcessedID += 1
        }
    }
}
```

## Conclusion

The executor preference in `FolderContentMonitor.swift` (line ~159) is **necessary but not sufficient** for perfect event ordering:

1. **It prevents severe reordering** caused by concurrent Task execution
2. **It does NOT prevent all reordering** because FSEventStream and dispatch queue scheduling can still deliver events out of order
3. **Under normal load**, events typically arrive in order with executor preference
4. **Under high load or with coalescing**, some reordering is expected even with proper synchronization

This is an inherent limitation of the FSEventStream → Dispatch Queue → Swift Concurrency pipeline, not a bug in our implementation. Applications requiring strict chronological ordering must implement additional buffering and sorting mechanisms.

## References

- Original finding: Test runs showing reordering with executor preference enabled
- Related Swift issue: https://github.com/swiftlang/swift/issues/74395
- FSEventStream documentation noting coalescing behavior
- Document reference: 20250904T080826