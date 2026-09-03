# FSEvents Flag Reference

*Document ID: 20260901T065000*
*Date: 2026-09-01*

Every bit of `FSEventStreamEventFlags`, what it obliges a consumer to do, and how this
library models it. Written because the stream-level flags were silently unmodelled until
2.1.0 and the failure mode was invisible.

## The partition

FSEvents packs two unrelated vocabularies into one word, and the bit layout separates them
cleanly:

| Range | Describes | Swift type |
|---|---|---|
| `0x01`–`0x80` (low byte) | the **stream** | `StreamCondition` |
| `0x100`–`0x400000` | the **item** at `eventPath` | `Change` |

No flag crosses the boundary, which is why `Change(eventFlags:)` and
`StreamCondition(eventFlags:)` are a mask and its complement. The two-level split is not a
design this library imposed; it is what the C API already does.

## Group A — lost events

Your derived state is now incomplete. Only a fresh directory listing can restore it.

| Flag | Bit | Obligation |
|---|---|---|
| `MustScanSubDirs` | `0x1` | Rescan `eventPath` **and all children, recursively**. |
| `UserDropped` | `0x2` | None. Diagnostic: buffering failed client-side (the likelier case). |
| `KernelDropped` | `0x4` | None. Diagnostic: buffering failed in the kernel. |

Only `MustScanSubDirs` is actionable — the headers are explicit that the other two exist to
help locate the bottleneck. It arises from *hierarchical coalescing*: a change in `~/Music`
and one in `~/Pictures` can arrive as a single event for `~`. When several paths are watched
on one stream, all of them are affected.

`StreamCondition.mustScanSubDirectories` is surfaced as `FolderContentChangeEvent.requiresRescan`.

## Group B — invalidated state

| Flag | Bit | Obligation |
|---|---|---|
| `EventIdsWrapped` | `0x8` | Discard any persisted event ID; it is no longer a valid `sinceWhen`. |
| `RootChanged` | `0x20` | A directory *along the path to* a watched path changed; the watched path may be gone. Event ID is zero. |
| `Mount` | `0x40` | A volume was mounted under a watched path. Do not scan it blindly — it may be huge or remote. |
| `Unmount` | `0x80` | A volume was unmounted; delivered after the fact. |

`RootChanged` is **unreachable as configured**. The headers say it is only ever sent when the
stream was created with `kFSEventStreamCreateFlagWatchRoot`, and this library passes only
`UseCFTypes | FileEvents`. Naming the flag does not make "someone renamed the folder you are
watching" observable; that needs a creation-flag change, which is tracked separately.

## Group C — sentinel

| Flag | Bit | Obligation |
|---|---|---|
| `HistoryDone` | `0x10` | Everything after this is live. **Ignore `eventPath`** — it is meaningless here. |

Only ever delivered when `sinceWhen` is not `kFSEventStreamEventIdSinceNow`, so consumers on
the default never see it.

## Item flags

The fifteen `0x100`-and-up flags map one-to-one onto `Change` members. Two are worth calling
out:

- `OwnEvent` (`0x80000`) — the change was caused by *this* process. Like `RootChanged`, it is
  **unreachable as configured**: the headers set it only for streams created with
  `kFSEventStreamCreateFlagMarkSelf`, which this library does not pass. Named for completeness,
  and because enabling it is the natural way to offer echo suppression.
- `ItemCloned` (`0x400000`) — `clonefile(2)`, or duplicating in Finder.

## Why a product, not a sum

An element carrying a condition normally carries no item flags: the headers describe `Mount`,
`Unmount`, `RootChanged` and `HistoryDone` as "a special event sent when…", and
`MustScanSubDirs` arises precisely from the loss of per-item detail.

But nothing in the API *guarantees* exclusivity, and `UserDropped`/`KernelDropped` are already
documented as being set "in addition to" `MustScanSubDirs`. So an `enum { case changed; case
condition }` would force an arbitrary rule for the both-set case and discard half the
information. `FolderContentChangeEvent` therefore carries **both** `change` and `condition`,
which is total: it represents whatever the kernel actually sent, including combinations we did
not anticipate.

`change.isEmpty` is the discriminator for a condition-only element. That test only works
because `Change(eventFlags:)` masks the low byte off — before 2.1.0 it stored the whole word,
so the word was never empty.

It is also coupled to `kFSEventStreamCreateFlagFileEvents`. Without that flag no item flag is
ever set, so every ordinary event would have an empty `Change` and the discriminator would
report each one as condition-only. Any future option that turns file-level events off has to
supply a different discriminator; it cannot simply become a flag.

## Ordering

Conditions and changes share one stream, interleaved in the order FSEvents produced them, and
that position carries meaning: changes reported *after* a `MustScanSubDirs` survive the rescan
it demands, while those *before* it are superseded. Splitting conditions into a second
`AsyncStream` would destroy the boundary, since a consumer could no longer tell which side of
it an event fell on. See [Bridging FSEventStream to AsyncStream.md](Bridging%20FSEventStream%20to%20AsyncStream.md)
for the wider ordering invariant.

## Consuming

```swift
for await event in stream {
    if event.requiresRescan {
        await rescan(event.url)          // baseline is stale, re-list recursively
    }
    guard !event.change.isEmpty else { continue }   // condition-only, no file to classify
    await handle(event)
}
```

## What this cost before 2.1.0

`Change.description` joins the names of the item flags it recognises. A `MustScanSubDirs`
element has `rawValue == 0x1`, which matches none of them, so `description` returned the empty
string: `swift run watch` printed `/Users/you/Notes (0) changed: ` and consumers testing
`change.contains(...)` got `false` for everything. FSEvents said "you have lost events, re-list
this tree" and it rendered as a blank line.
