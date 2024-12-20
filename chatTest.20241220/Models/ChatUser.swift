import CloudKit
import Foundation

struct ChatUser: Identifiable, Hashable {
    let id: String
    let appleId: String
    let recordName: String
    let name: String
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
            let appleId = record["appleId"] as? String,
            let name = record["name"] as? String,
            let email = record["email"] as? String
        else {
            throw CloudKitError.invalidRecord
        }

        self.id = id
        self.appleId = appleId
        self.recordName = record.recordID.recordName
        self.name = name
        self.email = email
        self.avatarAsset = record["avatar"] as? CKAsset
    }

    func toRecord() -> CKRecord {
        let record = CKRecord(recordType: "ChatUser")
        record["id"] = id
        record["appleId"] = appleId
        record["name"] = name
        record["email"] = email
        if let avatar = avatarAsset {
            record["avatar"] = avatar
        }
        return record
    }
}
