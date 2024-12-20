import Foundation
import OSLog

struct Logger {
    struct Category {
        let name: String

        static let app = Category(name: "🚀 App")
        static let cloudKit = Category(name: "☁️ CloudKit")
        static let database = Category(name: "💾 Database")
        static let network = Category(name: "🌐 Network")
        static let auth = Category(name: "🔐 Authentication")
    }

    private static let logger = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "App",
        category: "App"
    )

    static func info(_ message: String, category: Category) {
        os_log("ℹ️ %@: %@", log: logger, type: .info, category.name, message)
    }

    static func debug(_ message: String, category: Category) {
        os_log("🔍 %@: %@", log: logger, type: .debug, category.name, message)
    }

    static func error(_ message: String, category: Category) {
        os_log("❌ %@: %@", log: logger, type: .error, category.name, message)
    }

    static func error(_ error: Error, category: Category) {
        os_log("❌ %@: %@", log: logger, type: .error, category.name, String(describing: error))
    }
}
