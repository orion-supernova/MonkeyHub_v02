import Foundation

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
