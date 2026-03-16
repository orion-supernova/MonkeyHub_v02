import Foundation

enum RoomType: String, Codable {
    case regular = "Regular Room"
    case secret = "Chamber of Secrets"
}

struct ChatRoom: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let createdBy: String
    let createdAt: Date
    var lastMessage: String?
    var lastMessageDate: Date?
    var participants: [String]
    let description: String?
    var isPrivate: Bool
    let type: RoomType
    let messageLifetime: TimeInterval?
    var avatarStorageId: String?    // Convex storage ID
    var avatarURL: URL?             // Local cached avatar URL

    init(
        id: String = UUID().uuidString,
        name: String,
        createdBy: String,
        createdAt: Date = Date(),
        lastMessage: String? = nil,
        lastMessageDate: Date? = nil,
        participants: [String] = [],
        description: String? = nil,
        isPrivate: Bool = true,
        type: RoomType = .regular,
        messageLifetime: TimeInterval? = nil,
        avatarStorageId: String? = nil,
        avatarURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.lastMessage = lastMessage
        self.lastMessageDate = lastMessageDate
        self.participants = participants
        self.description = description
        self.isPrivate = isPrivate
        self.type = type
        self.messageLifetime = messageLifetime
        self.avatarStorageId = avatarStorageId
        self.avatarURL = avatarURL
    }

    // MARK: - Hashable / Equatable
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: ChatRoom, rhs: ChatRoom) -> Bool { lhs.id == rhs.id }
}
