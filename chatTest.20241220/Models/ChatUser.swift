import Foundation

struct ChatUser: Identifiable, Hashable {
    let id: String
    let name: String?
    let username: String
    let email: String
    let avatarStorageId: String?    // Convex storage ID
    let bio: String?
    let deviceTokens: [String]?
    let friendshipStatus: FriendshipStatus
    let requestId: String?
    let role: String?
    let status: String?            // "online" | "away" | "offline" (presence)
    let lastSeen: Date?
    let visibility: ProfileVisibility?  // self-view only; nil for other viewers
    let isRedacted: Bool           // some profile fields hidden by the subject's privacy
    let acceptsFriendRequests: Bool

    init(
        id: String,
        name: String? = nil,
        username: String,
        email: String,
        avatarStorageId: String? = nil,
        bio: String? = nil,
        deviceTokens: [String]? = nil,
        friendshipStatus: FriendshipStatus = .none,
        requestId: String? = nil,
        role: String? = nil,
        status: String? = nil,
        lastSeen: Date? = nil,
        visibility: ProfileVisibility? = nil,
        isRedacted: Bool = false,
        acceptsFriendRequests: Bool = true
    ) {
        self.id = id
        self.name = name
        self.username = username
        self.email = email
        self.avatarStorageId = avatarStorageId
        self.bio = bio
        self.deviceTokens = deviceTokens
        self.friendshipStatus = friendshipStatus
        self.requestId = requestId
        self.role = role
        self.status = status
        self.lastSeen = lastSeen
        self.visibility = visibility
        self.isRedacted = isRedacted
        self.acceptsFriendRequests = acceptsFriendRequests
    }

    /// Presence convenience.
    var isOnline: Bool { status == "online" }

    /// Best available display name — name, then username
    var displayName: String {
        if let name, !name.isEmpty { return name }
        return username.isEmpty ? "Unknown" : username
    }

    /// First letter for avatar placeholder
    var displayInitial: String {
        displayName.prefix(1).uppercased()
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: ChatUser, rhs: ChatUser) -> Bool { lhs.id == rhs.id }
}
