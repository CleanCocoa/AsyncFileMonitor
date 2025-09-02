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
	public let change: Change

	/// A `URL` representation of the ``eventPath``.
	public var url: URL { URL(fileURLWithPath: eventPath) }

	/// The filename component of the changed path.
	public var filename: String { url.lastPathComponent }

	/// A string representation of this change event.
	///
	/// Returns a formatted string containing the path, event ID, and change type.
	public var description: String { "\(eventPath) (\(eventID)) changed: \(change)" }

	/// Creates a new folder content change event.
	///
	/// - Parameters:
	///   - eventID: The unique event identifier from Core Services
	///   - eventPath: The file system path where the change occurred
	///   - change: The ``Change`` flags describing what happened
	public init(
		eventID: FSEventStreamEventId,
		eventPath: String,
		change: Change
	) {
		self.eventID = eventID
		self.eventPath = eventPath
		self.change = change
	}
}
