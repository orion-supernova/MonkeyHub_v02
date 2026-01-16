import CloudKit
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
    let assetURL: URL? // The active URL for the current session
    var status: MessageStatus
    var reactions: [MessageReaction]
    
    // System message identifier
    static let systemSenderId = "system"
    static let systemSenderName = "System"

    // CloudKit record keys
    static let recordType = "ChatMessage"
    static let idKey = "id"
    static let senderIdKey = "senderId"
    static let senderNameKey = "senderName"
    static let contentKey = "content"
    static let typeKey = "type"
    static let timestampKey = "timestamp"
    static let roomIdKey = "roomId"
    static let assetKey = "asset"

    // MARK: - Codable Strategy
    // We use a filename string for persistence because absolute URLs
    // break when the iOS App Sandbox UUID changes.
    enum CodingKeys: String, CodingKey {
        case id, senderId, senderName, content, type, timestamp, roomId, status, reactions
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
        self.assetURL = assetURL
        self.status = status
        self.reactions = reactions
    }

    // MARK: - Codable Implementation
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        senderId = try container.decode(String.self, forKey: .senderId)
        senderName = try container.decode(String.self, forKey: .senderName)
        content = try container.decode(String.self, forKey: .content)
        type = try container.decode(MessageType.self, forKey: .type)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        roomId = try container.decode(String.self, forKey: .roomId)
        status = try container.decode(MessageStatus.self, forKey: .status)
        reactions = try container.decode([MessageReaction].self, forKey: .reactions)
        
        // Re-base the URL: Get the filename and resolve it to the current sandbox path
        let fileName = try container.decodeIfPresent(String.self, forKey: .assetFileName)
        assetURL = AssetPersistenceService.shared.getURL(for: fileName)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(senderId, forKey: .senderId)
        try container.encode(senderName, forKey: .senderName)
        try container.encode(content, forKey: .content)
        try container.encode(type, forKey: .type)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(roomId, forKey: .roomId)
        try container.encode(status, forKey: .status)
        try container.encode(reactions, forKey: .reactions)
        
        // Persist ONLY the filename, not the absolute URL
        try container.encodeIfPresent(assetURL?.lastPathComponent, forKey: .assetFileName)
    }

    // MARK: - CloudKit Logic

    init(from record: CKRecord) throws {
        guard let id = record[ChatMessage.idKey] as? String,
            let senderId = record[ChatMessage.senderIdKey] as? String,
            let senderName = record[ChatMessage.senderNameKey] as? String,
            let content = record[ChatMessage.contentKey] as? String,
            let typeRaw = record[ChatMessage.typeKey] as? String,
            let type = MessageType(rawValue: typeRaw),
            let timestamp = record[ChatMessage.timestampKey] as? Date,
            let roomId = record[ChatMessage.roomIdKey] as? String
        else {
            throw CloudKitError.invalidRecord
        }

        self.id = id
        self.senderId = senderId
        self.senderName = senderName
        self.content = content
        self.type = type
        self.timestamp = timestamp
        self.roomId = roomId

        if let asset = record[ChatMessage.assetKey] as? CKAsset {
            self.assetURL = AssetPersistenceService.shared.persistAsset(asset)
        } else {
            self.assetURL = nil
        }
        
        self.reactions = []
        self.status = .sent
    }

    func toRecord() -> CKRecord {
        let recordID = CKRecord.ID(recordName: id)
        let record = CKRecord(recordType: ChatMessage.recordType, recordID: recordID)
        
        record[ChatMessage.idKey] = id
        record[ChatMessage.senderIdKey] = senderId
        record[ChatMessage.senderNameKey] = senderName
        record[ChatMessage.contentKey] = content
        record[ChatMessage.typeKey] = type.rawValue
        record[ChatMessage.timestampKey] = timestamp
        record[ChatMessage.roomIdKey] = roomId

        if let url = assetURL {
            record[ChatMessage.assetKey] = CKAsset(fileURL: url)
        }

        return record
    }
    
    // MARK: - Helpers

    func groupedReactions() -> [ReactionGroup] {
        let grouped = Dictionary(grouping: reactions, by: { $0.emoji })
        return grouped.map { ReactionGroup(emoji: $0.key, reactions: $0.value) }
            .sorted { $0.reactions.first?.timestamp ?? Date() < $1.reactions.first?.timestamp ?? Date() }
    }

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id &&
        lhs.status == rhs.status &&
        lhs.reactions.count == rhs.reactions.count &&
        lhs.assetURL == rhs.assetURL
    }
}
