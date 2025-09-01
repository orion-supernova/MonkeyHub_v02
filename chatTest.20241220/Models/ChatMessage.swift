import CloudKit
import Foundation

enum MessageType: String, Codable {
    case text
    case image
    case video
    case url
    case audio
}

struct ChatMessage: Identifiable, Equatable {
    let id: String
    let senderId: String
    let senderName: String
    let content: String
    let type: MessageType
    let timestamp: Date
    let roomId: String
    let assetURL: URL?

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

    init(
        id: String = UUID().uuidString,
        senderId: String,
        senderName: String,
        content: String,
        type: MessageType,
        timestamp: Date = Date(),
        roomId: String,
        assetURL: URL? = nil
    ) {
        self.id = id
        self.senderId = senderId
        self.senderName = senderName
        self.content = content
        self.type = type
        self.timestamp = timestamp
        self.roomId = roomId
        self.assetURL = assetURL
    }

    init?(from record: CKRecord) {
        guard let id = record[ChatMessage.idKey] as? String,
            let senderId = record[ChatMessage.senderIdKey] as? String,
            let senderName = record[ChatMessage.senderNameKey] as? String,
            let content = record[ChatMessage.contentKey] as? String,
            let typeRaw = record[ChatMessage.typeKey] as? String,
            let type = MessageType(rawValue: typeRaw),
            let timestamp = record[ChatMessage.timestampKey] as? Date,
            let roomId = record[ChatMessage.roomIdKey] as? String
        else {
            return nil
        }

        self.id = id
        self.senderId = senderId
        self.senderName = senderName
        self.content = content
        self.type = type
        self.timestamp = timestamp
        self.roomId = roomId

        if let asset = record[ChatMessage.assetKey] as? CKAsset {
            self.assetURL = asset.fileURL
        } else {
            self.assetURL = nil
        }
    }

    func toRecord() -> CKRecord {
        let record = CKRecord(recordType: ChatMessage.recordType)
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

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id
    }
}
