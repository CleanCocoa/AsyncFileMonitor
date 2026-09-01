//
//  FolderContentChangeEvent.swift
//  AsyncFileMonitor
//
//  Created by Christian Tietze on 08/11/16.
//  Copyright © 2016 Christian Tietze, RxSwiftCommunity (original RxFileMonitor)
//  Copyright © 2025 Christian Tietze (AsyncFileMonitor modernization)
//

import Foundation

/// Represents a file system change event.
///
/// This structure encapsulates information about a single file system event reported by Core Services,
/// including the event ID, the path that changed, and the type of ``Change`` that occurred.
public struct FolderContentChangeEvent: CustomStringConvertible, Sendable, Identifiable {

	/// Unique identifier for this event, conforming to `Identifiable`.
	///
	/// This is an alias for ``eventID`` to satisfy the `Identifiable` protocol.
	public var id: FSEventStreamEventId { eventID }

	/// The unique event identifier assigned by Core Services.
	public let eventID: FSEventStreamEventId

	/// The file system path where the change occurred.
	public let eventPath: String

	/// The type of change that occurred, represented as a ``Change`` option set.
	///
	/// Empty when this element reports only a ``condition`` and no file changed.
	public let change: Change

	/// Conditions the event stream reported alongside — or instead of — the change.
	///
	/// Usually empty. See ``StreamCondition`` for what each one obliges a consumer to do.
	public let condition: StreamCondition

	/// FSEvents dropped events: re-list ``eventPath`` recursively to restore derived state.
	public var requiresRescan: Bool { condition.contains(.mustScanSubDirectories) }

	/// A `URL` representation of the ``eventPath``.
	public var url: URL { URL(fileURLWithPath: eventPath) }

	/// The filename component of the changed path.
	public var filename: String { url.lastPathComponent }

	/// A string representation of this change event.
	///
	/// Returns a formatted string containing the path, event ID, and change type.
	public var description: String {
		if change.isEmpty && !condition.isEmpty {
			return "\(eventPath) (\(eventID)) stream condition: \(condition)"
		}
		var text = "\(eventPath) (\(eventID)) changed: \(change)"
		if !condition.isEmpty {
			text += ", stream condition: \(condition)"
		}
		return text
	}

	/// Creates a new folder content change event.
	///
	/// - Parameters:
	///   - eventID: The unique event identifier from Core Services
	///   - eventPath: The file system path where the change occurred
	///   - change: The ``Change`` flags describing what happened
	///   - condition: Conditions reported by the stream itself (default: none)
	public init(
		eventID: FSEventStreamEventId,
		eventPath: String,
		change: Change,
		condition: StreamCondition = []
	) {
		self.eventID = eventID
		self.eventPath = eventPath
		self.change = change
		self.condition = condition
	}
}
