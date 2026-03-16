import Foundation

enum MessageType: String, Codable {
    case text
    case image
    case video
    case url
    case audio
    case system
}

enum MessageStatus: String, Codable {
    case pending
    case sent
    case error
}

struct ChatMessage: Identifiable, Equatable, Codable {
    let id: String
    let senderId: String
    let senderName: String
    let content: String
    let type: MessageType
    let timestamp: Date
    let roomId: String
    var mediaStorageId: String?     // Convex storage ID for media assets
    var assetURL: URL?              // Local cached URL (not persisted as absolute path)
    var status: MessageStatus
    var reactions: [MessageReaction]

    static let systemSenderId = "system"
    static let systemSenderName = "System"

    // MARK: - Codable Strategy
    // Store filename only (not absolute URL) so it survives sandbox UUID rotation.
    enum CodingKeys: String, CodingKey {
        case id, senderId, senderName, content, type, timestamp, roomId
        case mediaStorageId, status, reactions
        case assetFileName
    }

    init(
        id: String = UUID().uuidString,
        senderId: String,
        senderName: String,
        content: String,
        type: MessageType,
        timestamp: Date = Date(),
        roomId: String,
        mediaStorageId: String? = nil,
        assetURL: URL? = nil,
        status: MessageStatus = .sent,
        reactions: [MessageReaction] = []
    ) {
        self.id = id
        self.senderId = senderId
        self.senderName = senderName
        self.content = content
        self.type = type
        self.timestamp = timestamp
        self.roomId = roomId
        self.mediaStorageId = mediaStorageId
        self.assetURL = assetURL
        self.status = status
        self.reactions = reactions
    }

    // MARK: - Codable

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        senderId = try c.decode(String.self, forKey: .senderId)
        senderName = try c.decode(String.self, forKey: .senderName)
        content = try c.decode(String.self, forKey: .content)
        type = try c.decode(MessageType.self, forKey: .type)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        roomId = try c.decode(String.self, forKey: .roomId)
        status = try c.decode(MessageStatus.self, forKey: .status)
        reactions = try c.decodeIfPresent([MessageReaction].self, forKey: .reactions) ?? []
        mediaStorageId = try c.decodeIfPresent(String.self, forKey: .mediaStorageId)

        // Re-base local asset URL from filename only
        let fileName = try c.decodeIfPresent(String.self, forKey: .assetFileName)
        assetURL = AssetPersistenceService.shared.getURL(for: fileName)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(senderId, forKey: .senderId)
        try c.encode(senderName, forKey: .senderName)
        try c.encode(content, forKey: .content)
        try c.encode(type, forKey: .type)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encode(roomId, forKey: .roomId)
        try c.encode(status, forKey: .status)
        try c.encode(reactions, forKey: .reactions)
        try c.encodeIfPresent(mediaStorageId, forKey: .mediaStorageId)
        // Persist filename only, not absolute URL
        try c.encodeIfPresent(assetURL?.lastPathComponent, forKey: .assetFileName)
    }

    // MARK: - Helpers

    func groupedReactions() -> [ReactionGroup] {
        Dictionary(grouping: reactions, by: { $0.emoji })
            .map { ReactionGroup(emoji: $0.key, reactions: $0.value) }
            .sorted { $0.reactions.first?.timestamp ?? Date() < $1.reactions.first?.timestamp ?? Date() }
    }

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id &&
        lhs.status == rhs.status &&
        lhs.reactions.count == rhs.reactions.count &&
        lhs.assetURL == rhs.assetURL
    }
}
