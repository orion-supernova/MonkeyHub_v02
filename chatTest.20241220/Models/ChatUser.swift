import CloudKit
import Foundation

struct ChatUser: Identifiable, Hashable {
    static let recordType = "ChatUser"

    let id: String
    let name: String
    let username: String
    let email: String
    let avatarAsset: CKAsset?
    let bio: String?  // Added in schema v2
    let deviceTokens: [String]?  // Changed to array in schema v4 to support multiple devices

    enum CodingKeys: String {
        case id
        case recordName
        case name
        case username
        case email
        case avatar  // Note: using 'avatar' to match CloudKit field name
        case bio     // Added in schema v2
        case deviceToken  // Legacy field (kept for migration)
        case deviceTokens  // Added in schema v4
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ChatUser, rhs: ChatUser) -> Bool {
        lhs.id == rhs.id
    }

    init(from record: CKRecord) throws {
        guard let id = record[CodingKeys.id.rawValue] as? String else {
            throw CloudKitError.invalidRecord
        }

        self.id = id
        self.name = record[CodingKeys.name.rawValue] as? String ?? ""
        self.username = record[CodingKeys.username.rawValue] as? String ?? ""
        self.email = record[CodingKeys.email.rawValue] as? String ?? ""
        self.avatarAsset = record[CodingKeys.avatar.rawValue] as? CKAsset
        self.bio = record[CodingKeys.bio.rawValue] as? String
        
        // Try to read deviceTokens array first, fallback to legacy deviceToken
        if let tokens = record[CodingKeys.deviceTokens.rawValue] as? [String] {
            self.deviceTokens = tokens
        } else if let token = record[CodingKeys.deviceToken.rawValue] as? String, !token.isEmpty {
            self.deviceTokens = [token]
        } else {
            self.deviceTokens = nil
        }
    }

    init(id: String, name: String, email: String) {
        self.id = id
        self.name = name
        self.username = ""
        self.email = email
        self.avatarAsset = nil
        self.bio = nil
        self.deviceTokens = nil
    }

    init(from existing: ChatUser, name: String, username: String, email: String) {
        self.id = existing.id
        self.name = name
        self.username = username
        self.email = email
        self.avatarAsset = existing.avatarAsset
        self.bio = existing.bio
        self.deviceTokens = existing.deviceTokens
    }
}

extension ChatUser {
    /// Convert to CloudKit record
    ///
    /// - Returns: CKRecord representation of this user
    func toRecord() -> CKRecord {
        // Let CloudKit generate a system UUID as the record ID (like existing records)
        // Don't force it to match the user's iCloud ID
        let record = CKRecord(recordType: Self.recordType)

        // Store the user's iCloud ID in the id FIELD (can have underscore)
        record[CodingKeys.id.rawValue] = id
        record[CodingKeys.name.rawValue] = name
        record[CodingKeys.username.rawValue] = username
        record[CodingKeys.email.rawValue] = email
        if let avatar = avatarAsset {
            record[CodingKeys.avatar.rawValue] = avatar
        }
        if let bio = bio {
            record[CodingKeys.bio.rawValue] = bio
        }
        if let deviceTokens = deviceTokens {
            record[CodingKeys.deviceTokens.rawValue] = deviceTokens
        }
        return record
    }
}