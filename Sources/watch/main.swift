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

		#if os(macOS)
		let platform = "macOS (FSEvents)"
		#elseif os(Linux)
		let platform = "Linux (libuv)"
		#else
		let platform = "Unknown"
		#endif

		print("🎯 Starting AsyncFileMonitor CLI (\(platform))")
		print("📁 Monitoring paths:")
		for path in paths {
			print("   • \(path)")
		}
		print("📡 Press Ctrl+C to stop monitoring\n")
		fflush(stdout)

		// Create the monitor stream using cross-platform API
		let stream = AsyncFileMonitor.monitor(paths: paths)

		// Monitor for changes
		for await event in stream {
			let timestamp = DateFormatter.timestamp.string(from: Date())
			let changeDescription = event.change.description.isEmpty ? "unknown" : event.change.description

			print("[\(timestamp)] 📄 \(event.eventPath)")
			print("                🔄 \(changeDescription)")
			print("                🆔 Event ID: \(event.eventID)")
			print("")
			fflush(stdout)
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
