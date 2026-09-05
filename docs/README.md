# AsyncFileMonitor Documentation

## Overview

This directory contains technical documentation for the AsyncFileMonitor library, with a focus on concurrency, event ordering, and architectural decisions.

## Documents

### [Event Ordering Analysis.md](Event%20Ordering%20Analysis.md)
*Historical.* Comprehensive analysis of event ordering in the file monitoring pipeline, including:
- The critical role of executor preference
- How to reproduce ordering issues
- Test results and findings
- Architecture overview

### [Event Reordering with Executor.md](Event%20Reordering%20with%20Executor.md)  
*Historical.* Detailed explanation of why events can still arrive out of order even WITH executor preference:
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

### [Testing FSEvents Code.md](Testing%20FSEvents%20Code.md)
What is provable about an FSEvents bridge and what is not:
- Why the default failure mode is a hang rather than a red test, and how to bound it
- `liveCount` is process-wide: how parallel suites make teardown assertions false-pass *and* false-fail
- Negative controls — the deliberate breakages that proved each teardown test can fail
- Which FSEvents conditions are reproducible on demand and which are flake generators
- Checking that the test command itself can fail

### [FSEvents Flag Reference.md](FSEvents%20Flag%20Reference.md)
Every `FSEventStreamEventFlags` bit, grouped by what it obliges a consumer to do:
- The low-byte/high-bits partition that `StreamCondition` and `Change` mirror
- Lost events, invalidated state, and the `HistoryDone` sentinel
- Why the event carries both a change and a condition rather than being a sum type
- Why `RootChanged` cannot fire without `kFSEventStreamCreateFlagWatchRoot`

### [Quick Reference.md](Quick%20Reference.md)
*Historical.* Points at the actor/executor implementation, including files that no longer exist.

### [Direct AsyncStream Approach.md](Direct%20AsyncStream%20Approach.md)
*Historical.* The direct-AsyncStream approach that replaced the actor/executor design, including the `MulticastAsyncStream` broadcaster that 3.0 removed. Kept for the stress-test results.

## Key Insights

The most important findings from our analysis:

### Actor/Executor Approach Limitations
> **Executor preference is necessary but not sufficient for perfect event ordering**

- **Without executor preference**: Severe reordering occurs consistently
- **With executor preference**: Mild reordering occurs only under high load
- **Root cause**: Multiple layers (FSEventStream, dispatch queues, Task creation) can each introduce timing variations

### Direct AsyncStream Breakthrough (Reference: 20250905T073442)
> **Bypassing Swift concurrency entirely eliminates ordering issues**

- **Direct FSEventStream → AsyncStream flow**: Perfect ordering under all tested conditions
- **No Task scheduling**: Events never cross async/await boundaries where reordering can occur

The multicast broadcaster this originally fanned out through was removed in 3.0; the ordering result is a property of the direct callback path, which remains.

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
FSEventStream → Dispatch Queue → C callback → AsyncStream continuation
```

There is no Task boundary in the path, which is what earlier designs needed executor preference to defend — and could not fully.