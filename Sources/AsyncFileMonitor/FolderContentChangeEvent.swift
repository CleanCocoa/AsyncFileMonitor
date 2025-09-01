//
//  FolderContentChangeEvent.swift
//  AsyncFileMonitor
//
//  Created by Christian Tietze on 08/11/16.
//  Copyright © 2016 Christian Tietze, RxSwiftCommunity (original RxFileMonitor)
//  Copyright © 2025 Christian Tietze (AsyncFileMonitor modernization)
//

import Foundation

public struct FolderContentChangeEvent: CustomStringConvertible, Sendable {

	public let eventID: FSEventStreamEventId
	public let eventPath: String
	public let change: Change

	public var url: URL { URL(fileURLWithPath: eventPath) }

	public var filename: String { url.lastPathComponent }

	public var description: String { "\(eventPath) (\(eventID)) changed: \(change)" }

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
