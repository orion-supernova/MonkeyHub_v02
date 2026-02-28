import Foundation
import CloudKit

struct MessageReaction: Identifiable, Codable, Equatable {
    let id: String
    let emoji: String
    let userId: String
    let messageId: String
    let timestamp: Date
    
    // CloudKit record keys
    static let recordType = "MessageReaction"
    static let idKey = "id"
    static let emojiKey = "emoji"
    static let userIdKey = "userId"
    static let messageIdKey = "messageId"  // Legacy string field
    static let messageReferenceKey = "messageReference"  // New reference field
    static let timestampKey = "timestamp"
    
    init(
        id: String = UUID().uuidString,
        emoji: String,
        userId: String,
        messageId: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.emoji = MessageReaction.normalizeEmoji(emoji)
        self.messageId = messageId
        self.timestamp = timestamp
    }
    
    /// Initialize from CloudKit record
    init(from record: CKRecord) throws {
        guard let id = record[MessageReaction.idKey] as? String,
              let emoji = record[MessageReaction.emojiKey] as? String,
              let userId = record[MessageReaction.userIdKey] as? String,
              let timestamp = record[MessageReaction.timestampKey] as? Date else {
            throw CloudKitError.invalidRecord
        }
        
        self.id = id
        self.emoji = MessageReaction.normalizeEmoji(emoji)
        self.userId = userId
        self.timestamp = timestamp
        
        // Try new reference field first, fallback to legacy string field
        if let messageReference = record[MessageReaction.messageReferenceKey] as? CKRecord.Reference {
            self.messageId = messageReference.recordID.recordName
        } else if let messageId = record[MessageReaction.messageIdKey] as? String {
            self.messageId = messageId
        } else {
            throw CloudKitError.invalidRecord
        }
    }
    
    func toRecord() -> CKRecord {
        let recordID = CKRecord.ID(recordName: id)
        let record = CKRecord(recordType: MessageReaction.recordType, recordID: recordID)
        
        record[MessageReaction.idKey] = id
        record[MessageReaction.emojiKey] = emoji
        record[MessageReaction.userIdKey] = userId
        record[MessageReaction.timestampKey] = timestamp
        
        // Store both for backward compatibility
        record[MessageReaction.messageIdKey] = messageId
        
        // Also create a reference for CASCADE DELETE (if schema supports it)
        let messageRecordID = CKRecord.ID(recordName: messageId)
        let messageReference = CKRecord.Reference(recordID: messageRecordID, action: .deleteSelf)
        record[MessageReaction.messageReferenceKey] = messageReference
        
        return record
    }
    
    static func == (lhs: MessageReaction, rhs: MessageReaction) -> Bool {
        lhs.id == rhs.id
    }

    static func normalizeEmoji(_ value: String) -> String {
        let strippedTextPresentation = value.replacingOccurrences(of: "\u{FE0E}", with: "")

        // Unify common variants to emoji presentation for stable cross-device equality/display.
        switch strippedTextPresentation {
        case "❤":
            return "❤️"
        default:
            return strippedTextPresentation
        }
    }
}

/// Aggregated reactions for UI display
struct ReactionGroup: Identifiable {
    let emoji: String
    let reactions: [MessageReaction]
    
    var id: String { emoji }
    var count: Int { reactions.count }
    var userIds: Set<String> { Set(reactions.map { $0.userId }) }
    
    func containsUser(_ userId: String) -> Bool {
        userIds.contains(userId)
    }
}
