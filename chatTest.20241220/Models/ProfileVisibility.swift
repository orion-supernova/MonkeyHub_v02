import Foundation

/// Who may see a given profile field. Mirrors the backend's per-field
/// visibility strings. New accounts default to `.nobody` (most private).
enum VisibilityLevel: String, Codable, CaseIterable, Identifiable {
    case everyone = "public"
    case friends
    case nobody

    var id: String { rawValue }

    var label: String {
        switch self {
        case .everyone: return "Everyone"
        case .friends: return "Friends"
        case .nobody: return "Nobody"
        }
    }
}

/// Per-field privacy settings (mirrors `users.visibility`). `friendRequests`
/// is binary (everyone/nobody) on the backend; we surface only those two in UI.
struct ProfileVisibility: Equatable {
    var avatar: VisibilityLevel
    var status: VisibilityLevel
    var lastSeen: VisibilityLevel
    /// Whether this user's read receipts ("Seen") are surfaced to senders.
    var seen: VisibilityLevel
    /// Whether others may send this user friend requests (everyone/nobody).
    var acceptsFriendRequests: Bool

    /// Default shown before the server value loads. Mirrors the backend
    /// `getProfile.canSee` contract: avatar/status/lastSeen are public when
    /// unset; read receipts (`seen`) are private (opt-in).
    static let `default` = ProfileVisibility(
        avatar: .everyone,
        status: .everyone,
        lastSeen: .everyone,
        seen: .nobody,
        acceptsFriendRequests: true
    )

    init(
        avatar: VisibilityLevel = .nobody,
        status: VisibilityLevel = .nobody,
        lastSeen: VisibilityLevel = .nobody,
        seen: VisibilityLevel = .nobody,
        acceptsFriendRequests: Bool = true
    ) {
        self.avatar = avatar
        self.status = status
        self.lastSeen = lastSeen
        self.seen = seen
        self.acceptsFriendRequests = acceptsFriendRequests
    }
}
