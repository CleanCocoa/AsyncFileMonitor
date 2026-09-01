//
//  StreamConditionTests.swift
//  AsyncFileMonitor
//

import Foundation
import Testing

@testable import AsyncFileMonitor

@Suite("StreamCondition")
struct StreamConditionTests {

	@Test("Item flags decode as a change with no stream condition")
	func itemFlagsCarryNoCondition() {
		let flags = FSEventStreamEventFlags(
			kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemIsFile
		)

		#expect(Change(eventFlags: flags) == [.created, .isFile])
		#expect(StreamCondition(eventFlags: flags).isEmpty)
	}

	@Test("Stream flags decode as a condition with no change")
	func streamFlagsCarryNoChange() {
		let flags = FSEventStreamEventFlags(
			kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagKernelDropped
		)

		#expect(StreamCondition(eventFlags: flags) == [.mustScanSubDirectories, .kernelDropped])
		#expect(Change(eventFlags: flags).isEmpty)
	}

	/// The C API never promises that an element carries only one kind of flag, so decoding must
	/// keep both rather than pick a winner.
	@Test("An element carrying both kinds keeps both")
	func mixedFlagsDecodeLosslessly() {
		let flags = FSEventStreamEventFlags(
			kFSEventStreamEventFlagItemModified | kFSEventStreamEventFlagMustScanSubDirs
		)

		#expect(Change(eventFlags: flags) == .modified)
		#expect(StreamCondition(eventFlags: flags) == .mustScanSubDirectories)
	}

	@Test("The two option sets partition the flag word")
	func maskIsAPartition() {
		let itemFlags = [
			kFSEventStreamEventFlagItemCreated, kFSEventStreamEventFlagItemRemoved,
			kFSEventStreamEventFlagItemInodeMetaMod, kFSEventStreamEventFlagItemRenamed,
			kFSEventStreamEventFlagItemModified, kFSEventStreamEventFlagItemFinderInfoMod,
			kFSEventStreamEventFlagItemChangeOwner, kFSEventStreamEventFlagItemXattrMod,
			kFSEventStreamEventFlagItemIsFile, kFSEventStreamEventFlagItemIsDir,
			kFSEventStreamEventFlagItemIsSymlink, kFSEventStreamEventFlagOwnEvent,
			kFSEventStreamEventFlagItemIsHardlink, kFSEventStreamEventFlagItemIsLastHardlink,
			kFSEventStreamEventFlagItemCloned,
		]
		let streamFlags = [
			kFSEventStreamEventFlagMustScanSubDirs, kFSEventStreamEventFlagUserDropped,
			kFSEventStreamEventFlagKernelDropped, kFSEventStreamEventFlagEventIdsWrapped,
			kFSEventStreamEventFlagHistoryDone, kFSEventStreamEventFlagRootChanged,
			kFSEventStreamEventFlagMount, kFSEventStreamEventFlagUnmount,
		]

		for flag in itemFlags {
			#expect(flag & StreamCondition.flagsMask == 0, "item flag \(flag) collides with the stream mask")
		}
		for flag in streamFlags {
			#expect(flag & ~StreamCondition.flagsMask == 0, "stream flag \(flag) collides with the item mask")
		}
	}

	@Test("A dropped-events element asks for a rescan and describes itself")
	func rescanIsVisible() {
		let event = FolderContentChangeEvent(
			eventID: 0,
			eventPath: "/tmp/watched",
			change: Change(eventFlags: FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)),
			condition: StreamCondition(eventFlags: FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs))
		)

		#expect(event.requiresRescan)
		#expect(event.description == "/tmp/watched (0) stream condition: mustScanSubDirectories")
	}

	@Test("An ordinary change neither asks for a rescan nor mentions conditions")
	func ordinaryChangeIsUnaffected() {
		let flags = FSEventStreamEventFlags(
			kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemIsFile
		)
		let event = FolderContentChangeEvent(
			eventID: 42,
			eventPath: "/tmp/watched/note.md",
			change: Change(eventFlags: flags),
			condition: StreamCondition(eventFlags: flags)
		)

		#expect(!event.requiresRescan)
		#expect(event.description == "/tmp/watched/note.md (42) changed: isFile, created")
	}
}
