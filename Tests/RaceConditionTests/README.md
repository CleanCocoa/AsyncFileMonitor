# Race Condition Tests

This test suite demonstrates the critical importance of proper threading and concurrency patterns in file system monitoring. The tests are organized as a progressive story showing what works, what breaks, and why.

## The Story

### 0️⃣ FSEventStream Baseline (`0_FSEventStreamBaseline.swift`)
**The Foundation: Doing It Right**

This test demonstrates the FSEventStream C API used correctly with proper thread safety. It serves as the gold standard baseline that proves FSEventStream can maintain perfect chronological ordering of file system events when implemented correctly.

- ✅ Thread-safe event collection with proper locking
- ✅ Serial dispatch queue for event processing 
- ✅ Perfect chronological ordering maintained under all stress levels
- ✅ Educational value: Shows the reference implementation

### 1️⃣ FSEventStream Race Conditions (`1_FSEventStreamRaceConditions.swift`) 
**What Happens When Threading Goes Wrong**

This test deliberately removes thread safety from the FSEventStream implementation to demonstrate the catastrophic effects of race conditions. The unsafe implementation shows real-world consequences of concurrent programming mistakes.

- ❌ No locking around shared mutable state
- ❌ Concurrent dispatch queue amplifies race conditions
- ❌ Data corruption and event loss under stress
- 🎓 Educational value: Tangible demonstration of race condition problems

### 2️⃣ Actor and Executor Coordination (`2_ActorExecutorCoordination.swift`)
**Swift Concurrency Layer Reality with Advanced Coordination**

This test examines how the original AsyncFileMonitor implementation using actors and executors behaves under different load conditions and demonstrates that even with sophisticated actor isolation and custom executor coordination (using direct copies of the actual library code), the fundamental Swift concurrency scheduling limitations persist.

- ❌ Only works under moderate load, may experience reordering under high stress (intermittent)

### 3️⃣ Event Ordering Regressions (`3_EventOrderingRegressions.swift`)
**Specific Ordering Guarantees and Edge Cases**

This test focuses on the critical executor preference implementation that maintains event ordering in AsyncFileMonitor. It includes both automated verification and manual regression procedures.

- 🔍 Automated demonstration of current correct behavior
- 🧪 High-stress test to detect ordering regressions  
- 📝 Manual procedures to verify executor preference necessity
- 🎓 Educational value: Deep dive into Swift concurrency execution control

## Test Infrastructure

### Test Infrastructure Organization

#### Helpers Directory
The `Helpers/` subdirectory contains shared infrastructure used across all tests:

- **`TestConfiguration.swift`** - Standard test scenarios and file creation utilities
- **`EventCollector.swift`** - Protocol-based event collection system (thread-safe vs unsafe)
- **`FSEventStreamTestRunner.swift`** - Concrete test runners and harness implementations  
- **`TestAssertions.swift`** - Shared assertion utilities and validation functions

#### 2_ActorExecutorCoordination Directory
The `2_ActorExecutorCoordination/` subdirectory contains the complete copied implementation for the actor/executor coordination baseline:

- **`TestFileSystemEventExecutor.swift`** - Direct copy of FileSystemEventExecutor for stable baseline
- **`TestFileSystemEventStream.swift`** - Direct copy of FileSystemEventStream for stable baseline  
- **`TestStreamRegistrar.swift`** - Direct copy of StreamRegistrar for stable baseline
- **`TestFolderContentMonitor.swift`** - Direct copy of FolderContentMonitor for stable baseline
- **`TestActorBasedFileMonitor.swift`** - Test wrapper using copied types for self-contained baseline

### Key Testing Patterns

1. **Parameterized Tests**: Use Swift Testing arguments to run the same test logic across different stress scenarios
2. **Known Issues Handling**: Use `withKnownIssue(isIntermittent: true)` for race conditions and concurrency edge cases
3. **Educational Assertions**: Tests document both success and failure modes for learning purposes
4. **Real FSEventStream Integration**: Tests use actual macOS FSEventStream API, not mocks

## Running the Tests

```bash
# Run all race condition tests
swift test --filter RaceConditionTests

# Run specific test files
swift test --filter 0_FSEventStreamBaseline
swift test --filter 1_FSEventStreamRaceConditions  
swift test --filter 2_ActorExecutorCoordination
swift test --filter 3_EventOrderingRegressions
```

## Expected Behavior

- **0_FSEventStreamBaseline**: Always passes - demonstrates perfect ordering
- **1_FSEventStreamRaceConditions**: Passes with known issues - demonstrates race conditions
- **2_ActorExecutorCoordination**: May show intermittent ordering issues under high stress, proving that even sophisticated executor coordination cannot eliminate Swift concurrency scheduling effects
- **3_EventOrderingRegressions**: Demonstrates both working and edge case behaviors

The combination of these tests provides confidence in AsyncFileMonitor's implementation while educating developers about the complexities and trade-offs in concurrent file system monitoring.
