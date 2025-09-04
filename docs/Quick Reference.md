# AsyncFileMonitor Quick Reference

## Critical Code Locations

### Event Ordering Protection (ref: 20250904T080826)
**File:** `Sources/AsyncFileMonitor/FolderContentMonitor.swift:161`
**Purpose:** Prevents event reordering race condition
```swift
Task(executorPreference: FileSystemEventExecutor.shared) {
    await self.broadcast(folderContentChangeEvents: events)
}
```
⚠️ **Never remove the `executorPreference` parameter!**

### Custom Executor
**File:** `Sources/AsyncFileMonitor/FileSystemEventExecutor.swift`
**Purpose:** Serial executor ensuring chronological event processing

### Isolation Assertions
**Where:** `FolderContentMonitor.start()` and `stop()`
**Purpose:** Verify code runs on correct executor during development

## Running Tests

### Basic Test Suite
```bash
swift test
```

### Event Ordering Tests
```bash
# Run the main ordering test
swift test --filter eventOrderingWithCoalescedEvents

# Run baseline regression test
swift test --filter demonstrateCorrectBehavior

# Run high-stress test
swift test --filter highStressOrderingTest
```

## How to Break It (For Testing)

1. Edit `FolderContentMonitor.swift`, 20250904T080826
2. Remove `executorPreference: FileSystemEventExecutor.shared`
3. Run tests - they should fail with event reordering
4. **Remember to restore the original code!**

## Documentation

- Full analysis: `docs/Event Ordering Analysis.md`
- This quick reference: `docs/Quick Reference.md`

## Key Insights

- **With executor preference**: Events mostly maintain chronological order
- **Without executor preference**: Events consistently arrive out of order
- **Under extreme load**: Some reordering may occur even with proper synchronization

## References

- [SE-0417: Task Executor Preference](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0417-task-executor-preference.md)
- Document ID: 20250904T080826
