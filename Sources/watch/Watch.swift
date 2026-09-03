import AsyncFileMonitor
import Foundation

@main
struct Watch {
	static func main() async {
		let arguments = CommandLine.arguments

		guard arguments.count >= 2 else {
			print("Usage: swift run watch <path-to-watch> [path-to-watch...]")
			print("Example: swift run watch /Users/username/Documents")
			print("Example: swift run watch /path/to/folder1 /path/to/folder2")
			return
		}

		let paths = Array(arguments.dropFirst())

		// Validate paths exist
		for path in paths {
			var isDirectory: ObjCBool = false
			guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
				print("Error: Path does not exist: \(path)")
				return
			}
		}

		print("🎯 Starting AsyncFileMonitor CLI")
		print("📁 Monitoring paths:")
		for path in paths {
			print("   • \(path)")
		}
		print("📡 Press Ctrl+C to stop monitoring\n")

		// Note: AsyncFileMonitorLogger removed for simplicity

		let stream: AsyncStream<FolderContentChangeEvent>
		do {
			stream = try FolderContentMonitor.makeStream(paths: paths)
		} catch {
			print("❌ Could not start monitoring: \(error)")
			exit(1)
		}

		// Monitor for changes
		for await event in stream {
			let timestamp = DateFormatter.timestamp.string(from: Date())
			print("[\(timestamp)] 📄 \(event.eventPath)")
			if !event.change.isEmpty {
				print("                🔄 \(event.change)")
			}
			if !event.condition.isEmpty {
				print("                ⚠️  \(event.condition)")
			}
			print("                🆔 Event ID: \(event.eventID)")
			print("")
		}
	}
}

extension DateFormatter {
	fileprivate static let timestamp: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateFormat = "HH:mm:ss.SSS"
		return formatter
	}()
}
