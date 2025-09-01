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

	public let eventId: FSEventStreamEventId
	public let eventPath: String
	public let change: Change

	public var url: URL { URL(fileURLWithPath: eventPath) }

	public var filename: String { url.lastPathComponent }

	public var description: String { "\(eventPath) (\(eventId)) changed: \(change)" }

	public init(
		eventId: FSEventStreamEventId,
		eventPath: String,
		change: Change
	) {
		self.eventId = eventId
		self.eventPath = eventPath
		self.change = change
	}
}
