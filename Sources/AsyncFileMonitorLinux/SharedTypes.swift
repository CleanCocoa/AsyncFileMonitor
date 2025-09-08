import Foundation

/// Cross-platform option set for representing file system change flags.
///
/// This structure provides a platform-independent interface for file system event flags,
/// compatible with both macOS FSEvents and Linux libuv fs_event systems.
public struct Change: OptionSet, Sendable {

	/// The raw integer value of the option set.
	public var rawValue: Int

	/// Creates a new ``Change`` instance with the specified raw value.
	///
	/// - Parameter rawValue: The raw integer value representing the change flags.
	public init(rawValue: Int) {
		self.rawValue = rawValue
	}

	// MARK: - File Type Flags

	/// The changed item is a directory.
	public static let isDirectory = Change(rawValue: 1 << 0)

	/// The changed item is a file.
	public static let isFile = Change(rawValue: 1 << 1)

	/// The changed item is a hard link.
	public static let isHardlink = Change(rawValue: 1 << 2)

	/// The changed item is the last hard link to a file that is being removed.
	public static let isLastHardlink = Change(rawValue: 1 << 3)

	/// The changed item is a symbolic link.
	public static let isSymlink = Change(rawValue: 1 << 4)

	// MARK: - Change Type Flags

	/// The item was created.
	public static let created = Change(rawValue: 1 << 5)

	/// The item was modified.
	public static let modified = Change(rawValue: 1 << 6)

	/// The item was removed.
	public static let removed = Change(rawValue: 1 << 7)

	/// The item was renamed.
	public static let renamed = Change(rawValue: 1 << 8)

	// MARK: - Metadata Change Flags

	/// The item's owner was changed.
	public static let changeOwner = Change(rawValue: 1 << 9)

	/// The item's Finder information was modified (macOS-specific).
	public static let finderInfoModified = Change(rawValue: 1 << 10)

	/// The item's inode metadata was modified.
	public static let inodeMetaModified = Change(rawValue: 1 << 11)

	/// The item's extended attributes were modified.
	public static let xattrsModified = Change(rawValue: 1 << 12)
}

extension Change: Hashable {

	/// Hashes the essential components of this change by feeding them into the given hasher.
	///
	/// - Parameter hasher: The hasher to use when combining the components of this instance.
	public func hash(into hasher: inout Hasher) {
		hasher.combine(rawValue)
	}
}

extension Change: CustomStringConvertible {

	/// A textual representation of the change flags.
	///
	/// Returns a comma-separated list of the active change types.
	public var description: String {
		var names: [String] = []
		if self.contains(.isDirectory) { names.append("isDir") }
		if self.contains(.isFile) { names.append("isFile") }
		if self.contains(.isHardlink) { names.append("isHardlink") }
		if self.contains(.isLastHardlink) { names.append("isLastHardlink") }
		if self.contains(.isSymlink) { names.append("isSymlink") }

		if self.contains(.created) { names.append("created") }
		if self.contains(.modified) { names.append("modified") }
		if self.contains(.removed) { names.append("removed") }
		if self.contains(.renamed) { names.append("renamed") }

		if self.contains(.changeOwner) { names.append("changeOwner") }
		if self.contains(.finderInfoModified) { names.append("finderInfoModified") }
		if self.contains(.inodeMetaModified) { names.append("inodeMetaModified") }
		if self.contains(.xattrsModified) { names.append("xattrsModified") }

		return names.joined(separator: ", ")
	}
}

/// Represents a cross-platform file system change event.
///
/// This structure encapsulates information about a single file system event,
/// providing a unified API for both macOS FSEvents and Linux libuv fs_event systems.
public struct FolderContentChangeEvent: CustomStringConvertible, Sendable, Identifiable {

	/// Unique identifier for this event, conforming to `Identifiable`.
	public let id: UInt64

	/// The unique event identifier (alias for backward compatibility).
	public var eventID: UInt64 { id }

	/// The file system path where the change occurred.
	public let eventPath: String

	/// The raw event flags from the underlying system.
	public let eventFlags: UInt32

	/// The type of change that occurred, represented as a ``Change`` option set.
	public let change: Change

	/// A `URL` representation of the ``eventPath``.
	public var url: URL { URL(fileURLWithPath: eventPath) }

	/// The filename component of the changed path.
	public var filename: String { url.lastPathComponent }

	/// A string representation of this change event.
	///
	/// Returns a formatted string containing the path, event ID, and change type.
	public var description: String { "\(eventPath) (\(id)) changed: \(change)" }

	/// Creates a new folder content change event.
	///
	/// - Parameters:
	///   - eventId: The unique event identifier
	///   - eventPath: The file system path where the change occurred
	///   - eventFlags: The raw event flags from the underlying system
	///   - change: The ``Change`` flags describing what happened
	public init(
		eventId: UInt64,
		eventPath: String,
		eventFlags: UInt32,
		change: Change
	) {
		self.id = eventId
		self.eventPath = eventPath
		self.eventFlags = eventFlags
		self.change = change
	}
}
