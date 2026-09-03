# AsyncFileMonitor Documentation

## Overview

This directory contains technical documentation for the AsyncFileMonitor library, with a focus on concurrency, event ordering, and architectural decisions.

## Documents

### [Event Ordering Analysis.md](Event%20Ordering%20Analysis.md)
Comprehensive analysis of event ordering in the file monitoring pipeline, including:
- The critical role of executor preference
- How to reproduce ordering issues
- Test results and findings
- Architecture overview

### [Event Reordering with Executor.md](Event%20Reordering%20with%20Executor.md)  
Detailed explanation of why events can still arrive out of order even WITH executor preference:
- Multiple sources of reordering in the pipeline
- Swift concurrency timing variations
- Real-world implications and solutions

### [FSEventStream Ordering Findings.md](FSEventStream%20Ordering%20Findings.md)
**Critical discovery**: Direct testing proves FSEventStream maintains perfect chronological ordering
- Minimal C API tests show 100% perfect ordering even under extreme stress  
- Reordering happens in the Swift concurrency layer, not FSEventStream
- Validates that executor preference is the right approach

### [Bridging FSEventStream to AsyncStream.md](Bridging%20FSEventStream%20to%20AsyncStream.md)
The constraints every FSEvents-to-`AsyncStream` bridge must satisfy, recorded as decisions already made:
- Why one FSEventStream per stream, and what the multicast shape cost before 3.0 removed it
- The five pieces no bridge can drop, and what the single-subscriber shape leaves out
- Holding a non-copyable stream in an escaping closure, and the deadlock invariant behind its `@unchecked Sendable`
- The exact teardown sequence, including the asynchronous context release callback
- FSEvents gotchas: blocking stop, failed start, file-level events, coalescing vs. atomicity

### [FSEvents Flag Reference.md](FSEvents%20Flag%20Reference.md)
Every `FSEventStreamEventFlags` bit, grouped by what it obliges a consumer to do:
- The low-byte/high-bits partition that `StreamCondition` and `Change` mirror
- Lost events, invalidated state, and the `HistoryDone` sentinel
- Why the event carries both a change and a condition rather than being a sum type
- Why `RootChanged` cannot fire without `kFSEventStreamCreateFlagWatchRoot`

### [Quick Reference.md](Quick%20Reference.md)
Quick reference guide for developers:
- Critical code locations
- Test commands
- How to break and fix event ordering

### [Direct AsyncStream Approach.md](Direct%20AsyncStream%20Approach.md)
**Superior Alternative**: Documentation of a direct AsyncStream approach that bypasses actors entirely:
- Eliminates Swift concurrency scheduling issues
- Uses MulticastAsyncStream with OrderedDictionary for perfect subscriber order
- Swift 6 Mutex for modern synchronization
- **Consistently maintains perfect ordering even under extreme stress**

## Key Insights

The most important findings from our analysis:

### Actor/Executor Approach Limitations
> **Executor preference is necessary but not sufficient for perfect event ordering**

- **Without executor preference**: Severe reordering occurs consistently
- **With executor preference**: Mild reordering occurs only under high load
- **Root cause**: Multiple layers (FSEventStream, dispatch queues, Task creation) can each introduce timing variations

### Direct AsyncStream Breakthrough (Reference: 20250905T073442)
> **Bypassing Swift concurrency entirely eliminates ordering issues**

- **Direct FSEventStream → MulticastAsyncStream flow**: Perfect ordering under all tested conditions
- **No Task scheduling**: Events never cross async/await boundaries where reordering can occur
- **OrderedDictionary subscribers**: Deterministic event delivery order
- **Swift 6 Mutex**: Modern, safe synchronization without actor overhead

## Reference IDs

Critical code sections are tagged with reference IDs for traceability:

- **20250904T080826**: Actor/executor approach implementation and analysis
- **20250905T073442**: Direct AsyncStream approach breakthrough

This allows tracing between:
- Source code comments
- Documentation
- Test files

## Testing

Run the event ordering tests:
```bash
# Basic test suite
swift test

# Specific ordering tests
swift test --filter eventOrderingWithCoalescedEvents
swift test --filter demonstrateCorrectBehavior
swift test --filter highStressOrderingTest
```

## Architecture

```
FSEventStream → Dispatch Queue → Task(executorPreference) → Actor → AsyncStream
                                  ↑
                                  Critical synchronization point
```

The executor preference at the Task creation point is the primary defense against event reordering, though it cannot prevent all reordering due to upstream buffering and scheduling.