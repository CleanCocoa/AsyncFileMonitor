# Bridging FSEventStream to AsyncStream

*Document ID: 20260831T124622*
*Date: 2026-08-31*

The constraints that shape every FSEvents-to-`AsyncStream` bridge. Written as a
record of decisions already made, so a future bridge — here or elsewhere — does
not rediscover them.

## One shape

Every stream owns its own `FSEventStream`, created synchronously by the factory and released
when the stream terminates. Independent streams are what callers actually want, and it is the
smaller mechanism.

Through 2.x a second shape existed: a `FolderContentMonitor` *instance* fanned one kernel
stream out to every subscriber it had handed out, so several consumers saw identical event IDs
in identical order. It was deleted in 3.0 because nothing used it that way — the sole consumer
called `makeStream()` once per instance — and because it made every feature cost twice.

Two properties were lost with it, both worth knowing before anyone reintroduces multicast:

- **Startup became synchronous.** The instance path created its `FSEventStream` inside a
  lifecycle `Task` on first-subscriber, so monitoring began some time after the caller
  returned. Anything reconciling events against a baseline captured at construction had a
  window it could not close.
- **A throwing factory became possible.** With creation back inside the caller's frame, a
  failure at create or start has somewhere to go. On the instance path the caller was long
  gone by the time `make` ran.

Note that the deleted shape gave one stream per *monitor instance*, not one per path — two
instances watching the same folder still opened two kernel streams. Deduplicating per path
across a process is a different feature, tracked separately.

## What the bridge must do

These six are not stylistic. Drop any one and the bridge is either unsound or
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

**Failure reported at construction, not as an element.** FSEvents fails only
while the stream is being set up, never once it is running. So the factory
throws and a returned stream is one that started — which makes "the stream
finished" mean consumer teardown and nothing else. Note this requires
`AsyncStream.makeStream()`; the trailing-closure initializer's build closure
cannot rethrow.

**A direct callback-to-continuation path.** The C callback calls
`continuation.yield` synchronously. No `Task`, no actor hop. This is the whole
ordering story: FSEvents delivers in order under every load this repo has
tested, and reordering appears only when events cross a Swift concurrency
boundary. See [FSEventStream Ordering Findings.md](FSEventStream%20Ordering%20Findings.md).

**`Sendable` event types.** Events cross from the dispatch queue into the
consumer's async context, so `FolderContentChangeEvent` and `Change` are
value types all the way down.

## What multicast cost

Everything below existed to serve multiple subscribers, and went away with them in 3.0.
Recorded so that reintroducing multicast starts from an accurate price list.

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
`Task` boundary the direct path exists to avoid. The same argument governs
batched versus per-event delivery: both are built at the source, in the
handler closure, rather than by adapting one stream into the other.

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

## Buffering

The bridge uses `AsyncStream`'s default `.unbounded` policy. That is a decision,
not an oversight, and it should survive contact with someone who thinks it looks
careless.

Measured on an M-series laptop: writing 20,000 files into a watched directory
produced 21,794 events in 2.85s — roughly **7,600 events/sec** sustained, at
about **140 bytes/event** by a rough accounting (realistically two to three
times that once Swift `String` heap allocations count). A consumer ten seconds
behind during heavy churn therefore holds tens of megabytes, then catches up.

Three reasons unbounded is the right default here:

- A burst is finite — the filesystem operation ends — so unbounded buffering
  converts a burst into latency plus transient memory, not permanent growth.
- The bounded alternative is worse for this library specifically.
  `.bufferingNewest(n)` drops silently, and what it drops includes the
  `mustScanSubDirectories` element telling a consumer its baseline is stale.
  That turns a visible backlog into silent divergence — the exact failure the
  condition exists to prevent.
- FSEvents already has bounded queues upstream and *reports* their overflow.
  A second drop point in this layer duplicates the mechanism minus the
  reporting.

The one case that would justify revisiting: a consumer that stops draining
entirely while the stream stays alive. Growth is then unbounded in time rather
than in burst size — but that is a consumer bug, and a buffering policy would
mask it rather than fix it. The useful response would be a way to observe the
backlog.

## Gotchas

1. **`FSEventStreamStop` blocks** until in-flight callbacks finish. Avoid it on
   the main thread in latency-sensitive code, and see the deadlock invariant
   above.
2. **`FSEventStreamStart` can fail, and the failure path needs `Invalidate`.**
   By the time `Start` runs, `FSEventStreamSetDispatchQueue` has already
   scheduled the stream, and the headers are explicit: *"you must eventually
   call FSEventStreamInvalidate() and it is an error to call
   FSEventStreamInvalidate() without having the stream either scheduled on a
   runloop or a dispatch queue."* So the error path is
   `Invalidate` → `Release`, the same order as `deinit` minus the `Stop`.
   Releasing alone leaves the queue holding the stream, so the context's
   release callback never runs and the handler box — with whatever it captures
   — leaks with it. Do not "simplify" this by setting the queue to `NULL`
   first; the header warns against that ordering specifically.

   This library shipped that bug from the beginning and no test could see it,
   because the live-stream counter is only incremented *after* a successful
   start. Errors-only paths need their own accounting.

   A failure must also reach the caller: a consumer holding an `AsyncStream`
   that never yields and never finishes hangs in `for await` forever. Since 3.0
   the factories throw, which is only possible because creation happens
   synchronously in the caller's frame — see "One shape".
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
