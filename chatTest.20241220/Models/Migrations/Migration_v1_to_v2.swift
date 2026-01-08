import CloudKit
import Foundation

/**
 Migration: Version 1 to Version 2

 ## Changes
 - Ensures all ChatUser records have `username` field (String, default: "")
 - Ensures all ChatUser records have `bio` field (String, default: "" for visibility in CloudKit)

 ## Data Impact
 - All existing ChatUser records will be updated with default values if missing
 - Estimated time: ~1 second per 100 users

 ## Breaking Changes
 - None. Old app versions will continue working and will simply ignore these fields.

 ## Rollback
 - Rollback is not needed (additive migration)
 - Old app versions will simply ignore the new fields

 ## Testing
 - Tested with mock user records
 - Tested with fresh installations
 - Tested with partial migration failure scenarios
 */
class Migration_v1_to_v2: CloudKitMigration {
    let fromVersion = 1
    let toVersion = 2
    let description = "Add username and bio fields to ChatUser"

    func migrate(database: CKDatabase) async throws {
        Logger.info("🚀 Starting migration v1 → v2: Add username and bio fields", category: .cloudKit)

        // Fetch all ChatUser records
        let records = try await CloudKitBatchOperations.batchFetch(
            recordType: ChatUser.recordType,
            predicate: NSPredicate(value: true),
            database: database
        )

        Logger.info("📊 Found \(records.count) ChatUser records to check", category: .cloudKit)

        // If no records, migration is complete
        guard !records.isEmpty else {
            Logger.info("ℹ️ No records to migrate", category: .cloudKit)
            return
        }

        // Add new fields with defaults if they don't exist
        var updatedRecords: [CKRecord] = []
        var addedUsername = 0
        var addedBio = 0

        for record in records {
            var needsUpdate = false

            // Add username field if missing
            if record[ChatUser.CodingKeys.username.rawValue] == nil {
                record[ChatUser.CodingKeys.username.rawValue] = ""
                needsUpdate = true
                addedUsername += 1
                Logger.info(
                    "➕ Adding username field to user: \(record[ChatUser.CodingKeys.id.rawValue] ?? "unknown")",
                    category: .cloudKit)
            }

            // Add bio field with empty string if missing
            // Note: CloudKit doesn't store nil values, so we use empty string for optional fields
            if record[ChatUser.CodingKeys.bio.rawValue] == nil {
                record[ChatUser.CodingKeys.bio.rawValue] = ""
                needsUpdate = true
                addedBio += 1
                Logger.info(
                    "➕ Adding bio field to user: \(record[ChatUser.CodingKeys.id.rawValue] ?? "unknown")",
                    category: .cloudKit)
            }

            if needsUpdate {
                updatedRecords.append(record)
            }
        }

        // Batch save updated records
        if !updatedRecords.isEmpty {
            Logger.info(
                "💾 Updating \(updatedRecords.count) ChatUser records (username: \(addedUsername), bio: \(addedBio))",
                category: .cloudKit)

            try await CloudKitBatchOperations.batchSave(
                records: updatedRecords,
                database: database,
                progress: { completed, total in
                    Logger.info(
                        "📈 Migration progress: \(completed)/\(total) records updated",
                        category: .cloudKit)
                }
            )
        } else {
            Logger.info("✅ All records already have the new fields", category: .cloudKit)
        }

        Logger.info("✅ Migration v1 → v2 completed successfully!", category: .cloudKit)
    }

    func rollback(database: CKDatabase) async throws {
        // For additive migrations, rollback is usually a no-op
        // Old app versions will simply ignore the new fields
        Logger.info(
            "Rollback v2 → v1: No action needed (additive migration - old app versions will ignore new fields)",
            category: .cloudKit)
    }

    func validate(database: CKDatabase) async throws -> Bool {
        // For this migration, we always run it if the schema version says v1
        // This ensures migration runs based on schema version, not field existence
        // (Useful when fields are stuck in CloudKit and can't be removed)
        Logger.info("🔍 Migration v1 → v2 will run based on schema version (not field validation)", category: .cloudKit)
        return true  // Always run when schema version indicates v1
    }
}
