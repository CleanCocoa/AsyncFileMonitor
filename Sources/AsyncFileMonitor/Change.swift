//
//  Change.swift
//  AsyncFileMonitor
//
//  Created by Christian Tietze on 08/11/16.
//  Copyright © 2016 Christian Tietze, RxSwiftCommunity (original RxFileMonitor)
//  Copyright © 2025 Christian Tietze (AsyncFileMonitor modernization)
//

import Foundation

/// Option set wrapper around some `FSEventStreamEventFlags` which are useful to monitor folders.
///
/// This structure provides a Swift-friendly interface to Core Services file system event flags,
/// allowing you to work with file system change notifications in a type-safe manner.
public struct Change: OptionSet, Sendable {

	/// The raw integer value of the option set.
	public var rawValue: Int

	/// Creates a new ``Change`` instance with the specified raw value.
	///
	/// - Parameter rawValue: The raw integer value representing the change flags.
	public init(rawValue: Int) {
		self.rawValue = rawValue
	}

	/// Extracts the item flags from Core Services event flags, discarding stream conditions.
	///
	/// The low byte of `FSEventStreamEventFlags` describes the stream rather than the item at
	/// `eventPath`; see ``StreamCondition``. Masking it off is what lets an empty ``Change``
	/// mean "this element reports no file change".
	public init(eventFlags: FSEventStreamEventFlags) {
		self.rawValue = Int(eventFlags) & ~StreamCondition.flagsMask
	}

	/// The changed item is a directory.
	public static let isDirectory = Change(rawValue: kFSEventStreamEventFlagItemIsDir)

	/// The changed item is a file.
	public static let isFile = Change(rawValue: kFSEventStreamEventFlagItemIsFile)

	/// The changed item is a hard link.
	public static let isHardlink = Change(rawValue: kFSEventStreamEventFlagItemIsHardlink)

	/// The changed item is the last hard link to a file that is being removed.
	public static let isLastHardlink = Change(rawValue: kFSEventStreamEventFlagItemIsLastHardlink)

	/// The changed item is a symbolic link.
	public static let isSymlink = Change(rawValue: kFSEventStreamEventFlagItemIsSymlink)

	/// The item was created.
	public static let created = Change(rawValue: kFSEventStreamEventFlagItemCreated)

	/// The item was modified.
	public static let modified = Change(rawValue: kFSEventStreamEventFlagItemModified)

	/// The item was removed.
	public static let removed = Change(rawValue: kFSEventStreamEventFlagItemRemoved)

	/// The item was renamed.
	public static let renamed = Change(rawValue: kFSEventStreamEventFlagItemRenamed)

	/// The item's owner was changed.
	public static let changeOwner = Change(rawValue: kFSEventStreamEventFlagItemChangeOwner)

	/// The item's Finder information was modified.
	public static let finderInfoModified = Change(rawValue: kFSEventStreamEventFlagItemFinderInfoMod)

	/// The item's inode metadata was modified.
	public static let inodeMetaModified = Change(rawValue: kFSEventStreamEventFlagItemInodeMetaMod)

	/// The item's extended attributes were modified.
	public static let xattrsModified = Change(rawValue: kFSEventStreamEventFlagItemXattrMod)

	/// The item was cloned, e.g. by `clonefile(2)` or duplicating in Finder.
	public static let cloned = Change(rawValue: kFSEventStreamEventFlagItemCloned)

	/// The change was caused by this process.
	///
	/// - Note: Never reported as configured. The Core Services headers set this flag only for
	///   streams created with `kFSEventStreamCreateFlagMarkSelf`, which this library does not
	///   pass, so echo suppression is not available yet.
	public static let ownEvent = Change(rawValue: kFSEventStreamEventFlagOwnEvent)
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
		if self.contains(.cloned) { names.append("cloned") }
		if self.contains(.ownEvent) { names.append("ownEvent") }

		return names.joined(separator: ", ")
	}
}
