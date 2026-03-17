import Foundation

/// Centralized logger for all Convex requests, responses, and app events.
/// All output goes to the Xcode console in a consistent, readable format.
final class AppLogger {
    static let shared = AppLogger()
    private init() {}

    // MARK: - Convex Network

    func logQuery(_ function: String, args: [String: Any]? = nil) {
        var msg = "🔵 QUERY  \(function)"
        if let args, !args.isEmpty { msg += "\n         args: \(formatArgs(args))" }
        print(msg)
    }

    func logQueryResult(_ function: String, result: String) {
        print("🔵 QUERY  \(function) → \(result)")
    }

    func logMutation(_ function: String, args: [String: Any]? = nil) {
        var msg = "🟣 MUTATION \(function)"
        if let args, !args.isEmpty { msg += "\n           args: \(formatArgs(args))" }
        print(msg)
    }

    func logMutationResult(_ function: String, result: String) {
        print("🟣 MUTATION \(function) → \(result)")
    }

    func logError(_ context: String, _ error: Error) {
        let msg = friendlyError(error)
        print("🔴 ERROR   \(context)\n           \(msg)")
    }

    // MARK: - Auth

    func logAuth(_ event: String) {
        print("🔑 AUTH    \(event)")
    }

    // MARK: - Subscription

    func logSubscription(_ event: String, function: String) {
        print("📡 SUB     \(function) — \(event)")
    }

    // MARK: - General

    func info(_ message: String) {
        print("⚪ INFO    \(message)")
    }

    // MARK: - Helpers

    private func formatArgs(_ args: [String: Any]) -> String {
        args.map { k, v in
            let valStr = "\(v)"
            let truncated = valStr.count > 80 ? String(valStr.prefix(80)) + "…" : valStr
            return "\(k): \(truncated)"
        }
        .sorted()
        .joined(separator: ", ")
    }

    /// Translates raw Convex/server error strings into readable messages.
    func friendlyError(_ error: Error) -> String {
        let raw = error.localizedDescription
        if raw.contains("WRONG_PASSWORD") { return "Wrong password." }
        if raw.contains("USER_NOT_FOUND") { return "No account found with that username." }
        if raw.contains("USERNAME_TAKEN") { return "That username is already taken." }
        if raw.contains("INVALID_RECOVERY_KEY") { return "Invalid recovery key." }
        if raw.contains("ArgumentValidationError") {
            // Extract the Path + Validator from the server error for quick debugging
            let lines = raw.components(separatedBy: "\n")
            let relevant = lines.filter { $0.contains("Path:") || $0.contains("Value:") || $0.contains("Validator:") }
            if !relevant.isEmpty { return relevant.joined(separator: " | ") }
        }
        return raw
    }
}
