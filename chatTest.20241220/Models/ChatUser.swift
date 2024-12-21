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

    // Add Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)  // Only hash by id since it's unique
    }

    static func == (lhs: ChatUser, rhs: ChatUser) -> Bool {
        lhs.id == rhs.id  // Compare only by id
    }

    init(from record: CKRecord) throws {
        guard
            let id = record["id"] as? String,
            let name = record["name"] as? String,
            let email = record["email"] as? String
        else {
            throw CloudKitError.invalidRecord
        }

        self.id = id
        self.recordName = record.recordID.recordName
        self.name = name
        self.username = record["username"] as? String ?? ""
        self.email = email
        self.avatarAsset = record["avatar"] as? CKAsset
    }

    func toRecord() -> CKRecord {
        let record = CKRecord(recordType: ChatUser.recordType)
        record["id"] = id
        record["name"] = name
        record["username"] = username
        record["email"] = email
        if let avatar = avatarAsset {
            record["avatar"] = avatar
        }
        return record
    }
}
