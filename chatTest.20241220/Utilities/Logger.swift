import Foundation
import OSLog

struct Logger {
    static let app = "🚀 App"
    static let cloudKit = "☁️ CloudKit"
    static let database = "💾 Database"
    static let network = "🌐 Network"

    private static let logger = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "App", category: "App")

    static func info(_ message: String, category: String = "") {
        os_log("ℹ️ %@: %@", log: logger, type: .info, category, message)
    }

    static func debug(_ message: String, category: String = "") {
        os_log("🔍 %@: %@", log: logger, type: .debug, category, message)
    }

    static func error(_ error: Error, context: String = "") {
        os_log("❌ [%@] %@", log: logger, type: .error, context, String(describing: error))
    }
}
