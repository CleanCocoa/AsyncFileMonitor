# Testing FSEvents Code

*Document ID: 20260905T071500*
*Date: 2026-09-05*

What is provable about an FSEvents bridge, what is not, and the specific ways
tests here have looked like coverage without being it. Written after a review
found three passing suites that could not fail.

## The default failure mode is a hang, not a red test

Almost every integration test here has the shape "wait for an event, assert
something about it". If the code stops delivering events, `await task.value`
never returns — so the test hangs until the harness kills it, and the
`#expect` is never reached. It reports as a timeout with no useful location.

Bound every wait. The pattern that works:

```swift
let task = Task { for await event in stream { … } }
try await Task.sleep(for: .milliseconds(1500))   // generous, fixed
task.cancel()                                     // forces the loop to exit
#expect(await task.value == expected)             // now this line is reachable
```

The cancel is what converts "no events ever arrived" from a hang into a
failure that names the assertion.

## `liveCount` is process-wide, so parallelism breaks it in both directions

`FileSystemEventStream.liveCount` is the only observable proof that teardown
reaches the kernel stream rather than merely dropping the Swift wrapper. Tests
sample a baseline, do something, then wait for the count to return to it.

Being process-wide, that is only sound if nothing else is creating streams:

- **False pass.** Another suite's stream is live when the baseline is sampled
  and is released during the test. The count falls to `<= baseline` even though
  this test's own stream leaked.
- **False failure.** Another suite holds streams live past this test's
  deadline, and the poll expires.

`.serialized` on the suite is necessary but *not sufficient* — it orders tests
within a suite, not across suites. `make test` therefore passes
`--no-parallel`, which costs about 50s against 5s. Keep every `liveCount`
assertion inside the serialized suite rather than beside the feature it covers.

The race-free alternative, where it is available, is a weak sentinel captured
by the event handler: per-stream, immune to the global counter. It works for
the RAII wrapper directly, but not through the public factories, which offer no
seam to inject a capturing handler.

## Prove a teardown test can fail before believing it

A leak test that cannot fail is worse than no test, because it reads as
coverage. Both times these were written, the check was the same: break the
teardown deliberately and confirm red.

```swift
// Negative control: retain every box instead of releasing it on termination.
enum LeakSink { static let kept = Mutex<[EventStreamBox]>([]) }
LeakSink.kept.withLock { $0.append(box) }
```

That turned all six teardown assertions red. An earlier test in this repo
asserted nothing at all and survived for months.

The same applies to feature tests. The batched-delivery assertion was checked
by making the batched factory yield single-element batches; the replay test by
hardcoding `kFSEventStreamEventIdSinceNow` in place of the configured
`sinceWhen`. Both went red, which is the only reason they are worth keeping.

## Stress tests that assert nothing catch only crashes

Several tests create hundreds of streams in a loop with no expectations. They
are honest crash detectors and worth keeping as that — but a leak of one
FSEventStream per iteration passes all of them. Pair them with one serialized
test that creates and drops N streams and then asserts the count returns to
baseline.

## What is reproducible on demand, and what is not

| Condition | Reproducible? |
|---|---|
| `Error.creationFailed` | Yes — pass an empty `paths` array |
| Historical replay + `historyDone` | Yes — capture a real event ID, change the folder unwatched, resume |
| A path that does not exist | Yes, and it is deliberately *not* an error |
| Batched (coalesced) delivery | Usually, with a latency window — inherently probabilistic |
| `Error.startFailed` | No. Apple documents `FSEventStreamStart` as something that "ought to always succeed" |
| `mustScanSubDirectories`, `userDropped`, `kernelDropped` | No — requires overflowing a kernel queue |
| `eventIDsWrapped` | No |
| `rootChanged`, `ownEvent` | Not as configured — need `WatchRoot` / `MarkSelf` creation flags |
| `mounted` / `unmounted` | Feasible via `hdiutil`, but slow and environment-dependent |

For the unreproducible ones, unit-test the flag decoding and stop there. A test
that tries to provoke a dropped-events condition is a flake generator.

## Replay reads a log, so writes need time to reach it

A `sinceWhen` test that writes a file and immediately opens the resuming stream
is racing FSEvents' own journal. It will pass under parallel load — which
supplies the delay incidentally — and fail the moment the suite runs serially.
Sleep between the write and the resuming stream, and say why in a comment.

## Check that the test command can fail

`make test` piped `swift test` into an output filter without `pipefail`, so the
pipeline's exit status was the filter's: it exited 0 regardless of results. The
filter also matched the run summary on a glyph and did not know the one used
for "passed with known issues", so it printed the build lines and nothing else.
Between them, `make test` was a constant.

Verify a test runner in both directions — break an assertion, confirm non-zero
exit and a visible failure; restore it, confirm zero and a visible summary.

Note for macOS: setting `pipefail` via `.SHELLFLAGS` silently does nothing,
because macOS ships GNU make 3.81 and that variable arrived in 3.82. Set it
inline in the recipe.
