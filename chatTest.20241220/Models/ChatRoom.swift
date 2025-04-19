import CloudKit
import Foundation

enum RoomType: String, Codable {
    case regular = "Regular Room"
    case secret = "Chamber of Secrets"
}

struct ChatRoom: Identifiable {
    let id: String
    let name: String
    let createdBy: String
    let createdAt: Date
    let lastMessage: String?
    let lastMessageDate: Date?
    let participants: [String]
    let description: String?
    let isPrivate: Bool?
    let type: RoomType
    let messageLifetime: TimeInterval?

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
        self.isPrivate = false
        self.type = type
        self.messageLifetime = messageLifetime
    }

    func toRecord() -> CKRecord {
        let record = CKRecord(recordType: ChatRoom.recordType)
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
        return record
    }
}
