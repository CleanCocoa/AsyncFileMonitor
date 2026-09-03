import Foundation
import Testing

@testable import AsyncFileMonitor

@Suite("Startup failure")
struct StreamFailureTests {

	@Test func `makeStream throws rather than returning a stream that never yields`() throws {
		#expect(throws: FolderContentMonitor.Error.creationFailed) {
			_ = try FolderContentMonitor.makeStream(paths: [])
		}
	}

	@Test func `makeBatchedStream throws on the same input`() throws {
		#expect(throws: FolderContentMonitor.Error.creationFailed) {
			_ = try FolderContentMonitor.makeBatchedStream(paths: [])
		}
	}

	/// FSEvents accepts a path that does not exist yet and reports its creation, so this is
	/// deliberately not a failure. Asserted so nobody "fixes" it into one.
	@Test func `a path that does not exist is not a startup failure`() throws {
		let missing = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString)
			.path

		_ = try FolderContentMonitor.makeStream(paths: [missing])
	}
}
