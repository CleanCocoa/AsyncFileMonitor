//
//  StreamCondition.swift
//  AsyncFileMonitor
//
//  Created by Christian Tietze on 2026-09-01.
//  Copyright © 2026 Christian Tietze
//

import Foundation

/// A condition reported by the event stream itself, rather than a change to a file.
///
/// FSEvents packs two unrelated vocabularies into one `FSEventStreamEventFlags` word: the low
/// byte describes the *stream*, everything from `0x100` up describes the *item* at `eventPath`.
/// ``StreamCondition`` covers the former, ``Change`` the latter.
///
/// Conditions arrive as ordinary elements of the event stream, interleaved with file changes in
/// the order FSEvents produced them. That position is meaningful: file changes reported after
/// ``mustScanSubDirectories`` survive the rescan it demands, while those before it are superseded
/// by it. An element carrying a condition usually carries no ``Change``, but the C API does not
/// guarantee this, so both are always reported.
public struct StreamCondition: OptionSet, Sendable {

	/// The raw integer value of the option set.
	public var rawValue: Int

	/// Creates a new ``StreamCondition`` with the specified raw value.
	public init(rawValue: Int) {
		self.rawValue = rawValue
	}

	/// Extracts the stream conditions from Core Services event flags, discarding item flags.
	public init(eventFlags: FSEventStreamEventFlags) {
		self.rawValue = Int(eventFlags) & StreamCondition.flagsMask
	}

	/// The bits of `FSEventStreamEventFlags` that describe the stream rather than an item.
	static let flagsMask = 0xFF

	// MARK: - Lost events

	/// Events were dropped: rescan ``FolderContentChangeEvent/eventPath`` **and all of its
	/// children, recursively**.
	///
	/// Set when events were coalesced hierarchically — a change in `~/Music` and one in
	/// `~/Pictures` may arrive as a single event for `~`. Any state derived from the event
	/// stream alone is now incomplete; only a fresh directory listing can restore it.
	///
	/// This is the sole actionable condition in this group: ``userDropped`` and
	/// ``kernelDropped`` only say where the bottleneck was.
	public static let mustScanSubDirectories = StreamCondition(rawValue: kFSEventStreamEventFlagMustScanSubDirs)

	/// Diagnostic accompanying ``mustScanSubDirectories``: buffering failed on the client side.
	///
	/// Per the Core Services headers, the likelier of the two.
	public static let userDropped = StreamCondition(rawValue: kFSEventStreamEventFlagUserDropped)

	/// Diagnostic accompanying ``mustScanSubDirectories``: buffering failed in the kernel.
	public static let kernelDropped = StreamCondition(rawValue: kFSEventStreamEventFlagKernelDropped)

	// MARK: - Invalidated state

	/// The 64-bit event ID counter wrapped around.
	///
	/// Previously issued event IDs are no longer valid values for `sinceWhen`. Callers that
	/// persist an event ID as a resume point must discard it.
	public static let eventIDsWrapped = StreamCondition(rawValue: kFSEventStreamEventFlagEventIdsWrapped)

	/// A directory along the path to a monitored path changed; the monitored path may no longer exist.
	///
	/// The event ID is zero and `eventPath` is the monitored path that was affected.
	///
	/// - Note: Only ever delivered when the stream was created with
	///   `kFSEventStreamCreateFlagWatchRoot`, which this library does not currently pass.
	public static let rootChanged = StreamCondition(rawValue: kFSEventStreamEventFlagRootChanged)

	/// A volume was mounted underneath a monitored path; `eventPath` is the mount point.
	///
	/// - Warning: The new volume may contain an arbitrarily large hierarchy, and may not be
	///   local. Do not scan it unconditionally.
	public static let mounted = StreamCondition(rawValue: kFSEventStreamEventFlagMount)

	/// A volume was unmounted underneath a monitored path; `eventPath` is the directory it was
	/// unmounted from.
	///
	/// Delivered after the unmount has already happened.
	public static let unmounted = StreamCondition(rawValue: kFSEventStreamEventFlagUnmount)

	// MARK: - Sentinel

	/// Marks the end of the historical events replayed for a `sinceWhen` other than
	/// `kFSEventStreamEventIdSinceNow`; everything after it is live.
	///
	/// - Important: `eventPath` is meaningless on this event and must be ignored.
	public static let historyDone = StreamCondition(rawValue: kFSEventStreamEventFlagHistoryDone)
}

extension StreamCondition: Hashable {

	public func hash(into hasher: inout Hasher) {
		hasher.combine(rawValue)
	}
}

extension StreamCondition: CustomStringConvertible {

	/// A comma-separated list of the active conditions.
	public var description: String {
		var names: [String] = []
		if self.contains(.mustScanSubDirectories) { names.append("mustScanSubDirectories") }
		if self.contains(.userDropped) { names.append("userDropped") }
		if self.contains(.kernelDropped) { names.append("kernelDropped") }

		if self.contains(.eventIDsWrapped) { names.append("eventIDsWrapped") }
		if self.contains(.rootChanged) { names.append("rootChanged") }
		if self.contains(.mounted) { names.append("mounted") }
		if self.contains(.unmounted) { names.append("unmounted") }

		if self.contains(.historyDone) { names.append("historyDone") }

		return names.joined(separator: ", ")
	}
}
