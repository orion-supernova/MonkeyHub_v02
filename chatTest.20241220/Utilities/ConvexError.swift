import Foundation

// MARK: - Lifetime Formatter

/// Formats a message lifetime in seconds into a human-readable string.
/// Examples: 10 → "10s", 90 → "1m 30s", 3600 → "1h", 3660 → "1h 1m"
func formatLifetime(_ seconds: TimeInterval) -> String {
    let s = Int(seconds)
    if s < 60 { return "\(s)s" }
    if s < 3600 {
        let m = s / 60; let r = s % 60
        return r == 0 ? "\(m)m" : "\(m)m \(r)s"
    }
    let h = s / 3600; let m = (s % 3600) / 60
    return m == 0 ? "\(h)h" : "\(h)h \(m)m"
}

// MARK: - Error Messages

/// Extracts a user-friendly message from a Convex/UniFFI error.
func friendlyErrorMessage(_ error: Error, fallback: String = "Something went wrong. Please try again.") -> String {
    let raw = error.localizedDescription
    if raw.contains("NOT_AUTHORIZED") || raw.contains("NOT_OWNER") {
        return "You don't have permission to do that."
    }
    if raw.contains("NOT_FOUND") || raw.contains("NOT_A_MEMBER") {
        return "This room or user could not be found."
    }
    if raw.contains("ROOM_NAME_TAKEN") || raw.contains("ROOM_EXISTS") {
        return "That room name is already taken."
    }
    if raw.contains("network") || raw.contains("Network") || raw.contains("offline") {
        return "You appear to be offline. Please check your connection."
    }
    return fallback
}
