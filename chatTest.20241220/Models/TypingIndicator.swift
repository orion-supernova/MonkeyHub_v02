import Foundation
import CloudKit

/// Represents an ephemeral typing state for a user in a chat room
struct TypingIndicator: Identifiable, Equatable {
    let id: String
    let roomId: String
    let userId: String
    let userName: String
    let timestamp: Date
    let expiresAt: Date
    
    // CloudKit record keys
    static let recordType = "TypingIndicator"
    static let idKey = "id"
    static let roomIdKey = "roomId"
    static let userIdKey = "userId"
    static let userNameKey = "userName"
    static let timestampKey = "timestamp"
    static let expiresAtKey = "expiresAt"
    
    init(roomId: String, userId: String, userName: String) {
        self.id = "\(roomId)_\(userId)"
        self.roomId = roomId
        self.userId = userId
        self.userName = userName
        self.timestamp = Date()
        self.expiresAt = Date().addingTimeInterval(5) // 5 second TTL
    }
    
    init(from record: CKRecord) throws {
        guard
            let id = record[TypingIndicator.idKey] as? String,
            let roomId = record[TypingIndicator.roomIdKey] as? String,
            let userId = record[TypingIndicator.userIdKey] as? String,
            let userName = record[TypingIndicator.userNameKey] as? String,
            let timestamp = record[TypingIndicator.timestampKey] as? Date,
            let expiresAt = record[TypingIndicator.expiresAtKey] as? Date
        else {
            throw CloudKitError.invalidRecord
        }
        
        self.id = id
        self.roomId = roomId
        self.userId = userId
        self.userName = userName
        self.timestamp = timestamp
        self.expiresAt = expiresAt
    }
    
    func toRecord() -> CKRecord {
        let recordID = CKRecord.ID(recordName: id)
        let record = CKRecord(recordType: TypingIndicator.recordType, recordID: recordID)
        
        record[TypingIndicator.idKey] = id
        record[TypingIndicator.roomIdKey] = roomId
        record[TypingIndicator.userIdKey] = userId
        record[TypingIndicator.userNameKey] = userName
        record[TypingIndicator.timestampKey] = timestamp
        record[TypingIndicator.expiresAtKey] = expiresAt
        
        return record
    }
    
    var isExpired: Bool {
        Date() > expiresAt
    }
    
    static func == (lhs: TypingIndicator, rhs: TypingIndicator) -> Bool {
        lhs.id == rhs.id
    }
}