//
//  TestHelpers.swift
//  AsyncFileMonitorTests
//
//  Created by Christian Tietze on 08/11/16.
//  Copyright © 2025 Christian Tietze (AsyncFileMonitor test helpers)
//

import Foundation

@testable import AsyncFileMonitor

extension FolderContentChangeEvent {

	/// Checks if this event matches the given path and change criteria.
	/// Useful for testing when you want to check for specific change types on specific files.
	func matches(path: String? = nil, filename: String? = nil, change: Change? = nil) -> Bool {
		if let path = path, eventPath != path {
			return false
		}
		if let filename = filename, self.filename != filename {
			return false
		}
		if let change = change, !self.change.contains(change) {
			return false
		}
		return true
	}
}
