import Foundation

struct ChatUser: Identifiable, Hashable {
    let id: String
    let name: String?
    let username: String
    let email: String
    let avatarStorageId: String?    // Convex storage ID
    let bio: String?
    let deviceTokens: [String]?

    init(
        id: String,
        name: String? = nil,
        username: String = "",
        email: String = "",
        avatarStorageId: String? = nil,
        bio: String? = nil,
        deviceTokens: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.username = username
        self.email = email
        self.avatarStorageId = avatarStorageId
        self.bio = bio
        self.deviceTokens = deviceTokens
    }

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
