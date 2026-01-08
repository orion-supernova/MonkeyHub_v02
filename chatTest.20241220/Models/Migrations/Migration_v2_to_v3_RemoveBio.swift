import CloudKit
import Foundation

/**
 Migration: Version 2 to Version 3 (Example: Remove Bio Field)

 ## Changes
 - Removes `bio` field from all ChatUser records

 ## Data Impact
 - All bio data will be permanently deleted
 - Estimated time: ~1 second per 100 users

 ## Breaking Changes
 - Apps on v2 will see empty bio fields after this migration
 - Make sure all users have updated to v3+ before running

 ## Rollback
 - Cannot restore deleted bio data
 - Only run this migration if you're sure bio is no longer needed

 ## Testing
 - Backup production data before running
 - Test on development environment first

 ## Usage
 This is an EXAMPLE template showing how to remove fields.
 To actually use it:
 1. Uncomment the registration in MigrationManifest.swift
 2. Update currentSchemaVersion in CloudKitManager.swift to 3
 3. Test thoroughly before deploying
 */
class Migration_v2_to_v3_RemoveBio: CloudKitMigration {
    let fromVersion = 2
    let toVersion = 3
    let description = "Remove bio field from ChatUser (EXAMPLE)"

    func migrate(database: CKDatabase) async throws {
        Logger.info("🚀 Starting migration v2 → v3: Remove bio field", category: .cloudKit)

        // Fetch all ChatUser records
        let records = try await CloudKitBatchOperations.batchFetch(
            recordType: ChatUser.recordType,
            predicate: NSPredicate(value: true),
            database: database
        )

        Logger.info("📊 Found \(records.count) ChatUser records to update", category: .cloudKit)

        guard !records.isEmpty else {
            Logger.info("ℹ️ No records to migrate", category: .cloudKit)
            return
        }

        // Remove bio field from all records
        var updatedRecords: [CKRecord] = []
        var removedCount = 0

        for record in records {
            // Check if bio field exists
            if record[ChatUser.CodingKeys.bio.rawValue] != nil {
                // Setting to nil will delete the field from the record
                record[ChatUser.CodingKeys.bio.rawValue] = nil
                updatedRecords.append(record)
                removedCount += 1

                Logger.info(
                    "🗑️ Removing bio field from user: \(record[ChatUser.CodingKeys.id.rawValue] ?? "unknown")",
                    category: .cloudKit)
            }
        }

        // Batch save updated records
        if !updatedRecords.isEmpty {
            Logger.info(
                "💾 Updating \(updatedRecords.count) ChatUser records (removed bio: \(removedCount))",
                category: .cloudKit)

            try await CloudKitBatchOperations.batchSave(
                records: updatedRecords,
                database: database,
                progress: { completed, total in
                    Logger.info(
                        "📈 Migration progress: \(completed)/\(total) records updated",
                        category: .cloudKit)
                },
                savePolicy: .allKeys  // Use allKeys to ensure nil values are processed
            )
        } else {
            Logger.info("✅ All records already have bio field removed", category: .cloudKit)
        }

        Logger.info("✅ Migration v2 → v3 completed successfully!", category: .cloudKit)
    }

    func rollback(database: CKDatabase) async throws {
        Logger.info(
            "⚠️ Rollback v3 → v2: Cannot restore deleted bio data",
            category: .cloudKit)
        // Bio data is lost, cannot rollback
        throw MigrationError.rollbackFailed(version: toVersion, reason: "Cannot restore deleted bio data")
    }

    func validate(database: CKDatabase) async throws -> Bool {
        Logger.info("🔍 Validating if migration v2 → v3 is needed...", category: .cloudKit)

        let query = CKQuery(recordType: ChatUser.recordType, predicate: NSPredicate(value: true))

        do {
            let (records, _) = try await database.records(matching: query, resultsLimit: 10)

            guard !records.isEmpty else {
                Logger.info("✅ No ChatUser records found - migration not needed", category: .cloudKit)
                return false
            }

            // Check if any records still have the bio field
            for (_, result) in records {
                let record = try result.get()
                let hasBio = record[ChatUser.CodingKeys.bio.rawValue] != nil

                if hasBio {
                    Logger.info("⚠️ Found records with bio field - migration needed", category: .cloudKit)
                    return true  // Migration needed
                }
            }

            Logger.info("✅ All sampled records have bio removed - migration not needed", category: .cloudKit)
            return false  // All records already migrated

        } catch let error as CKError where error.code == .unknownItem {
            Logger.info("✅ No ChatUser records found - migration not needed", category: .cloudKit)
            return false
        }
    }
}

// MARK: - Steps to Remove Bio Field Completely

/**
 ## Complete Bio Removal Checklist

 ### Step 1: Stop Writing to Bio (v3)
 1. Remove bio field from ChatUser creation/update UI
 2. Keep bio in model (optional, for backwards compatibility)
 3. Deploy to all users

 ### Step 2: Remove Field Values (v4)
 1. Enable this migration by uncommenting in MigrationManifest
 2. Update CloudKitManager currentSchemaVersion to 3
 3. Test on development environment
 4. Deploy to production
 5. Migration runs, deletes all bio values

 ### Step 3: Remove from Model (v5)
 1. Remove `bio` property from ChatUser.swift:
    ```swift
    // Delete this line:
    let bio: String?
    ```

 2. Remove bio from initializers and toRecord()

 3. Clean build and test

 ### Step 4: Clean Up CloudKit Schema (Optional)
 1. Go to CloudKit Dashboard
 2. Development → Record Types → ChatUser
 3. Find "bio" field in schema
 4. Click delete (trash icon)
 5. Deploy schema changes
 6. Repeat for Production when ready

 Note: Step 4 is optional - leaving the field definition in schema doesn't hurt anything.
 */
