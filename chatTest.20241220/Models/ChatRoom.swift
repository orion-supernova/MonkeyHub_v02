import CloudKit
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
    var isPrivate: Bool?
    let type: RoomType
    let messageLifetime: TimeInterval?
    var avatarAsset: CKAsset?

    // CloudKit record keys
    static let recordType = "ChatRoom"
    static let idKey = "id"
    static let nameKey = "name"
    static let createdByKey = "createdBy"
    static let createdAtKey = "createdAt"
    static let lastMessageKey = "lastMessage"
    static let lastMessageDateKey = "lastMessageDate"
    static let participantsKey = "participants"
    static let descriptionKey = "description"
    static let isPrivateKey = "isPrivate"
    static let typeKey = "type"
    static let messageLifetimeKey = "messageLifetime"
    static let avatarAssetKey = "avatarAsset"

    // Codable keys (excluding avatarAsset since CKAsset is not Codable)
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdBy
        case createdAt
        case lastMessage
        case lastMessageDate
        case participants
        case description
        case isPrivate
        case type
        case messageLifetime
    }

    init(from record: CKRecord) throws {
        guard
            let id = record[ChatRoom.idKey] as? String,
            let name = record[ChatRoom.nameKey] as? String,
            let createdBy = record[ChatRoom.createdByKey] as? String
        else {
            throw CloudKitError.invalidRecord
        }

        self.id = id
        self.name = name
        self.createdBy = createdBy

        // Handle both String and Date formats for createdAt
        if let createdAtDate = record[ChatRoom.createdAtKey] as? Date {
            self.createdAt = createdAtDate
        } else if let createdAtString = record[ChatRoom.createdAtKey] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            self.createdAt = formatter.date(from: createdAtString) ?? Date()
        } else {
            self.createdAt = Date()
        }

        self.lastMessage = record[ChatRoom.lastMessageKey] as? String
        self.lastMessageDate = record[ChatRoom.lastMessageDateKey] as? Date
        self.participants = (record[ChatRoom.participantsKey] as? [String]) ?? [createdBy]
        self.description = record[ChatRoom.descriptionKey] as? String
        self.isPrivate = record[ChatRoom.isPrivateKey] as? Bool
        self.type =
            RoomType(rawValue: record[ChatRoom.typeKey] as? String ?? "Regular Room") ?? .regular
        self.messageLifetime = record[ChatRoom.messageLifetimeKey] as? TimeInterval
        
        // Persist avatar asset to permanent storage
        if let asset = record[ChatRoom.avatarAssetKey] as? CKAsset {
            // Create a new CKAsset with the persisted URL
            if let persistedURL = AssetPersistenceService.shared.persistAsset(asset) {
                self.avatarAsset = CKAsset(fileURL: persistedURL)
            } else {
                self.avatarAsset = asset
            }
        } else {
            self.avatarAsset = nil
        }
    }

    init(
        name: String, createdBy: String, participants: [String] = [], type: RoomType = .regular,
        messageLifetime: TimeInterval? = nil
    ) {
        self.id = UUID().uuidString
        self.name = name
        self.createdBy = createdBy
        self.createdAt = Date()
        self.lastMessage = nil
        self.lastMessageDate = nil
        self.participants = participants
        self.description = nil
        self.isPrivate = true  // Default to private
        self.type = type
        self.messageLifetime = messageLifetime
        self.avatarAsset = nil
    }

    // Custom Decodable init - avatarAsset will be nil when decoded from JSON
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdBy = try container.decode(String.self, forKey: .createdBy)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastMessage = try container.decodeIfPresent(String.self, forKey: .lastMessage)
        lastMessageDate = try container.decodeIfPresent(Date.self, forKey: .lastMessageDate)
        participants = try container.decode([String].self, forKey: .participants)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        isPrivate = try container.decodeIfPresent(Bool.self, forKey: .isPrivate)
        type = try container.decode(RoomType.self, forKey: .type)
        messageLifetime = try container.decodeIfPresent(TimeInterval.self, forKey: .messageLifetime)
        avatarAsset = nil // CKAsset cannot be decoded from JSON
    }

    // Custom Encodable - skip avatarAsset since it's not Codable
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(createdBy, forKey: .createdBy)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(lastMessage, forKey: .lastMessage)
        try container.encodeIfPresent(lastMessageDate, forKey: .lastMessageDate)
        try container.encode(participants, forKey: .participants)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(isPrivate, forKey: .isPrivate)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(messageLifetime, forKey: .messageLifetime)
    }

    func toRecord() -> CKRecord {
        let recordID = CKRecord.ID(recordName: id)
        let record = CKRecord(recordType: ChatRoom.recordType, recordID: recordID)
        
        record[ChatRoom.idKey] = id
        record[ChatRoom.nameKey] = name
        record[ChatRoom.createdByKey] = createdBy
        record[ChatRoom.createdAtKey] = createdAt
        record[ChatRoom.lastMessageKey] = lastMessage
        record[ChatRoom.lastMessageDateKey] = lastMessageDate
        record[ChatRoom.participantsKey] = participants
        if let description = description {
            record[ChatRoom.descriptionKey] = description
        }
        if let isPrivate = isPrivate {
            record[ChatRoom.isPrivateKey] = isPrivate
        }
        record[ChatRoom.typeKey] = type.rawValue
        if let messageLifetime = messageLifetime {
            record[ChatRoom.messageLifetimeKey] = messageLifetime
        }
        if let avatarAsset = avatarAsset {
            record[ChatRoom.avatarAssetKey] = avatarAsset
        }
        return record
    }

    // MARK: - Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ChatRoom, rhs: ChatRoom) -> Bool {
        lhs.id == rhs.id
    }
}