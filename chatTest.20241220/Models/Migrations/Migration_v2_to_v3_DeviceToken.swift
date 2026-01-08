import CloudKit
import Foundation

/**
 Migration: Version 2 to Version 3

 ## Changes
 - Adds `deviceToken` field to ChatUser records (String?, default: "" for CloudKit visibility)

 ## Purpose
 - Enable push notifications for chatroom users
 - Store APNs device tokens in CloudKit for notification delivery

 ## Data Impact
 - All existing ChatUser records will be updated with empty deviceToken field
 - Users will need to re-register their device tokens on next app launch
 - Estimated time: ~1 second per 100 users

 ## Breaking Changes
 - None. Old app versions will continue working and will simply ignore this field.

 ## Rollback
 - Rollback is not needed (additive migration)
 - Old app versions will simply ignore the new field

 ## Testing
 - Tested with mock user records
 - Tested with fresh installations
 - Tested with partial migration failure scenarios
 */
class Migration_v2_to_v3_DeviceToken: CloudKitMigration {
    let fromVersion = 2
    let toVersion = 3
    let description = "Add deviceToken field to ChatUser for push notifications"

    func migrate(database: CKDatabase) async throws {
        Logger.info("🚀 Starting migration v2 → v3: Add deviceToken field", category: .cloudKit)

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

        // Add deviceToken field with default empty string if it doesn't exist
        var updatedRecords: [CKRecord] = []
        var addedDeviceToken = 0

        for record in records {
            var needsUpdate = false

            // Add deviceToken field if missing
            // Note: CloudKit doesn't store nil values, so we use empty string for optional fields
            if record[ChatUser.CodingKeys.deviceToken.rawValue] == nil {
                record[ChatUser.CodingKeys.deviceToken.rawValue] = ""
                needsUpdate = true
                addedDeviceToken += 1
                Logger.info(
                    "➕ Adding deviceToken field to user: \(record[ChatUser.CodingKeys.id.rawValue] ?? "unknown")",
                    category: .cloudKit)
            }

            if needsUpdate {
                updatedRecords.append(record)
            }
        }

        // Batch save updated records
        if !updatedRecords.isEmpty {
            Logger.info(
                "💾 Updating \(updatedRecords.count) ChatUser records (deviceToken: \(addedDeviceToken))",
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
            Logger.info("✅ All records already have the deviceToken field", category: .cloudKit)
        }

        Logger.info("✅ Migration v2 → v3 completed successfully!", category: .cloudKit)
    }

    func rollback(database: CKDatabase) async throws {
        // For additive migrations, rollback is usually a no-op
        // Old app versions will simply ignore the new field
        Logger.info(
            "Rollback v3 → v2: No action needed (additive migration - old app versions will ignore deviceToken field)",
            category: .cloudKit)
    }

    func validate(database: CKDatabase) async throws -> Bool {
        // For this migration, we always run it if the schema version says v2
        // This ensures migration runs based on schema version, not field existence
        Logger.info("🔍 Migration v2 → v3 will run based on schema version (not field validation)", category: .cloudKit)
        return true  // Always run when schema version indicates v2
    }
}
