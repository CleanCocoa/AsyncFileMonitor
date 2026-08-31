# Bridging FSEventStream to AsyncStream

*Document ID: 20260831T124622*
*Date: 2026-08-31*

The constraints that shape every FSEvents-to-`AsyncStream` bridge, and the two
shapes this library ships. Written as a record of decisions already made, so a
future bridge — here or elsewhere — does not rediscover them.

## Two shapes

The library exposes the same events through two arrangements, and the choice
between them is about FSEventStream ownership, not about the API surface.

| | `FolderContentMonitor.makeStream(url:)` (static) | `FolderContentMonitor(url:).makeStream()` (instance) |
|---|---|---|
| FSEventStreams | One per returned stream | One, shared by every stream the instance hands out |
| Subscribers | Exactly one | Many, in registration order |
| Lifetime | Tied to the returned stream | Starts at the first stream, stops after the last |
| Machinery | `AsyncStream` + one RAII wrapper | Adds a multicast registry, a `Mutex` state machine, a lifecycle task |

Prefer the static form. It is the smaller mechanism, and independent streams
are what most callers actually want. Reach for an instance only when several
consumers must observe *identical* events — the same event IDs, in the same
order — from a single kernel stream.

## What both shapes must do

These five are not stylistic. Drop any one and the bridge is either unsound or
misordered.

**A non-copyable RAII wrapper.** `FileSystemEventStream` is a `~Copyable`
struct whose `deinit` runs the `FSEventStreamStop` → `Invalidate` → `Release`
sequence. Non-copyability is what makes cleanup exactly-once: there is no
second owner that could stop the stream twice or keep it alive past its
consumer.

**A box for the C context.** `FSEventStreamContext` carries one opaque
pointer, so the event handler closure travels inside a `final class`
(`EventHandlerBox`) reached through `Unmanaged`. A box rather than `self`
avoids the initialization-order problem of handing a partially built value to
a C callback.

**Retain/release callbacks on the context.** Without them the box can be freed
while the C side still holds the pointer. With them, `FSEventStreamRelease`
drops the last reference and the box dies with the stream.

**A direct callback-to-continuation path.** The C callback calls
`continuation.yield` synchronously. No `Task`, no actor hop. This is the whole
ordering story: FSEvents delivers in order under every load this repo has
tested, and reordering appears only when events cross a Swift concurrency
boundary. See [FSEventStream Ordering Findings.md](FSEventStream%20Ordering%20Findings.md).

**`Sendable` event types.** Events cross from the dispatch queue into the
consumer's async context, so `FolderContentChangeEvent` and `Change` are
value types all the way down.

## What the single-subscriber shape leaves out

Everything below exists to serve multiple subscribers. With one consumer per
stream, each is cost without benefit.

| Component | Why it is unnecessary |
|---|---|
| Multicast registry | One continuation, not a collection |
| `Mutex<State>` | No state shared between subscribers |
| `idle`/`awaitingSubscribers`/`streaming` enum | The lifecycle is linear: create, run, tear down |
| Lifecycle event stream and its task | Nothing to coordinate start/stop against |
| `OrderedDictionary` of continuations | Registration order is meaningless with one subscriber |
| Inner/outer stream wrapping | The stream can be returned directly |

The last one is not merely simpler. Wrapping an inner stream in an outer one
requires a task to pump events between them, and that task is exactly the
`Task` boundary the direct path exists to avoid.

## Stream configuration

Two creation-time choices are load-bearing.

```swift
let flags = UInt32(
	kFSEventStreamCreateFlagUseCFTypes    // paths arrive as a CFArray
		| kFSEventStreamCreateFlagFileEvents  // file-level, not just directory-level
)
let queue = DispatchQueue(label: "FileSystemEventStream", qos: .userInteractive)
```

`kFSEventStreamCreateFlagUseCFTypes` is coupled to the callback: it is what
makes `eventPaths` a `CFArray`, which the callback unwraps through
`Unmanaged<CFArray>` and bridges to `[String]`. Drop the flag and that cast
becomes wrong, silently.

The queue's QoS decides how event delivery is prioritized against the rest of
the process. `.userInteractive` suits a UI observing a folder the user is
looking at; a background indexer would reasonably want lower. It is currently
fixed rather than a parameter.

## Non-copyable values and escaping closures

The bridge needs the FSEventStream to live as long as the `AsyncStream` and
die with it, which means the termination handler must hold it. But a
`~Copyable` value cannot be captured by an escaping closure.

Resolved here with `EventStreamBox`, a `final class` that consumes the stream
and gives the closure an ordinary reference to hold:

```swift
let box = EventStreamBox(eventStream)
continuation.onTermination = { _ in
    withExtendedLifetime(box) {}
}
```

Two things about this are easy to get wrong.

**The capture is the mechanism, not the body.** The stream stays alive because
the closure *holds* the box; it is released when `AsyncStream` drops the
termination handler after firing it. A body that looks like a no-op is doing
its job. Deleting it as dead code silently reintroduces a leaked kernel
stream that nothing else will catch.

**`@unchecked Sendable` rests on one invariant.** `deinit` runs on whichever
thread releases the box, and `FSEventStreamStop` blocks until in-flight
callbacks on the stream's own dispatch queue have returned. Releasing the last
reference *from* that queue — that is, from inside an event handler —
deadlocks. Nothing in the current design can do so, which is what makes the
conformance safe; a future change that terminates a stream from within its own
callback would break it.

An alternative is to make the wrapper a `final class` outright and skip the
box. That trades away the compile-time exactly-once guarantee for one less
type. The box keeps both.

## Teardown, precisely

1. The consumer breaks, cancels, or drops the stream.
2. `AsyncStream` invokes `onTermination`, then releases the handler.
3. Releasing the handler releases the box, running `FileSystemEventStream.deinit`.
4. `deinit` runs `FSEventStreamStop` → `Invalidate` → `Release`.
5. `Release` schedules the context release callback, which frees the handler box.

**Step 5 is asynchronous.** The context release callback runs on the stream's
dispatch queue, not inside the `FSEventStreamRelease` call. A test that
asserts the handler was freed immediately after release will fail; poll with a
deadline instead.

Teardown is covered by `Tests/AsyncFileMonitorTests/StreamTeardownTests.swift`.
`FileSystemEventStream.liveCount` is the seam: an internal counter of started
and not-yet-released streams, the only observable proof that teardown reaches
the kernel stream rather than merely dropping the Swift wrapper. The suite is
serialized because that counter is process-wide.

When changing this area, verify the tests still detect a leak — retain the box
in a static and confirm the static-path tests go red. A teardown test that
cannot fail is worse than none, because it reads as coverage.

## Gotchas

1. **`FSEventStreamStop` blocks** until in-flight callbacks finish. Avoid it on
   the main thread in latency-sensitive code, and see the deadlock invariant
   above.
2. **`FSEventStreamStart` can fail.** If it returns false, `FSEventStreamRelease`
   must still be called or the CF object leaks. A failure at either creation
   step must also end the stream — otherwise the consumer holds an
   `AsyncStream` that never yields and never finishes, and its `for await`
   loop hangs forever.
3. **`kFSEventStreamCreateFlagFileEvents` is essential.** Without it you get
   directory-level notifications only.
4. **Latency controls coalescing, not atomicity.** `0.0` delivers immediately;
   a larger value batches rapid changes. No latency makes a save look atomic:
   applications write to a temporary file and rename, and the OS interleaves
   metadata changes of its own, so one logical save surfaces as several events
   naming several paths. Consumers must expect this. See
   [UnderstandingEvents.md](../Sources/AsyncFileMonitor/Documentation.docc/UnderstandingEvents.md).
5. **Use `takeUnretainedValue` in the C callback.** The context callbacks
   already hold a retain; `takeRetainedValue` over-releases.
