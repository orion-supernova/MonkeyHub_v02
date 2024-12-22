import CloudKit
import Foundation

struct ChatUser: Identifiable, Hashable {
    static let recordType = "ChatUser"

    let id: String
    let recordName: String
    let name: String
    let username: String
    let email: String
    let avatarAsset: CKAsset?

    enum CodingKeys: String {
        case id
        case recordName
        case name
        case username
        case email
        case avatar  // Note: using 'avatar' to match CloudKit field name
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
        self.recordName = record.recordID.recordName
        self.name = record[CodingKeys.name.rawValue] as? String ?? ""
        self.username = record[CodingKeys.username.rawValue] as? String ?? ""
        self.email = record[CodingKeys.email.rawValue] as? String ?? ""
        self.avatarAsset = record[CodingKeys.avatar.rawValue] as? CKAsset
    }

    init(id: String, name: String, email: String) {
        self.id = id
        self.recordName = id
        self.name = name
        self.username = ""
        self.email = email
        self.avatarAsset = nil
    }
}

extension ChatUser {
    var asCKRecord: CKRecord {
        let record = CKRecord(recordType: Self.recordType)
        record[CodingKeys.id.rawValue] = id
        record[CodingKeys.name.rawValue] = name
        record[CodingKeys.username.rawValue] = username
        record[CodingKeys.email.rawValue] = email
        if let avatar = avatarAsset {
            record[CodingKeys.avatar.rawValue] = avatar
        }
        return record
    }
}
