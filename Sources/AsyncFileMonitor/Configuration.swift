//
//  Configuration.swift
//  AsyncFileMonitor
//
//  Created by Christian Tietze on 2026-09-03.
//  Copyright © 2026 Christian Tietze
//

import Foundation

extension FolderContentMonitor {

	/// How a monitoring stream is set up.
	///
	/// Every field has a default, so `Configuration()` is the configuration the factories use
	/// when none is given. Options are gathered here rather than spread across the factory
	/// signatures so that adding one does not change any existing call site.
	public struct Configuration: Sendable {

		/// The event to resume from.
		///
		/// `kFSEventStreamEventIdSinceNow` reports only changes made after monitoring starts.
		/// A stored event ID replays what happened since, followed by a
		/// ``StreamCondition/historyDone`` sentinel.
		///
		/// - Important: A stored ID stops being valid once
		///   ``StreamCondition/eventIDsWrapped`` is reported.
		public var sinceWhen: FSEventStreamEventId

		/// Seconds to wait before reporting, so related changes coalesce into one callback.
		///
		/// `0` delivers immediately. A larger value groups rapid changes, which
		/// ``FolderContentMonitor/makeBatchedStream(url:configuration:)`` then surfaces as a
		/// batch. It does not make a save atomic: see <doc:UnderstandingEvents>.
		public var latency: CFTimeInterval

		/// - Parameters:
		///   - sinceWhen: The event to resume from (default: only changes from now on)
		///   - latency: Coalescing interval in seconds (default: `0`, deliver immediately)
		public init(
			sinceWhen: FSEventStreamEventId = FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
			latency: CFTimeInterval = 0
		) {
			self.sinceWhen = sinceWhen
			self.latency = latency
		}
	}
}
