import CloudKit
import Foundation

/**
 Migration: Version 2 to Version 3

 ## Changes
 - Converts `deviceToken` (String) to `deviceTokens` ([String]) in ChatUser records
 - Clears old `deviceToken` field data after migration
 - Adds `avatarAsset` field support to ChatRoom records (CKAsset?, optional)

 ## Purpose
 - Support multiple devices per user for push notifications
 - Enable room avatars for visual customization

 ## Data Impact
 - All existing ChatUser records with deviceToken will have it migrated to deviceTokens array
 - Old deviceToken field will be cleared (set to nil)
 - Estimated time: ~1 second per 100 records

 ## Breaking Changes
 - Old app versions (v2) will NOT work after this migration
 - All users MUST update to v3+

 ## Rollback
 - Not supported. Once migrated, old deviceToken data is lost.
 */
class Migration_v2_to_v3: CloudKitMigration {
    let fromVersion = 2
    let toVersion = 3
    let description = "Migrate deviceToken to deviceTokens array"

    func migrate(database: CKDatabase) async throws {
        Logger.info("🚀 Starting migration v2 → v3", category: .cloudKit)

        try await migrateUsers(database: database)

        Logger.info("✅ Migration v2 → v3 completed successfully!", category: .cloudKit)
    }
    
    private func migrateUsers(database: CKDatabase) async throws {
        Logger.info("📱 Migrating ChatUser records (deviceToken → deviceTokens)...", category: .cloudKit)
        
        let records = try await CloudKitBatchOperations.batchFetch(
            recordType: ChatUser.recordType,
            predicate: NSPredicate(value: true),
            database: database
        )

        Logger.info("📊 Found \(records.count) ChatUser records to migrate", category: .cloudKit)

        guard !records.isEmpty else {
            Logger.info("ℹ️ No ChatUser records to migrate", category: .cloudKit)
            return
        }

        var updatedRecords: [CKRecord] = []
        var migrated = 0

        for record in records {
            // Migrate old deviceToken to new deviceTokens array
            if let oldToken = record[ChatUser.CodingKeys.deviceToken.rawValue] as? String, !oldToken.isEmpty {
                record[ChatUser.CodingKeys.deviceTokens.rawValue] = [oldToken]
                migrated += 1
                Logger.info(
                    "➕ Migrating deviceToken to deviceTokens for user: \(record[ChatUser.CodingKeys.id.rawValue] ?? "unknown")",
                    category: .cloudKit)
            } else {
                // No old token, set empty array
                record[ChatUser.CodingKeys.deviceTokens.rawValue] = [String]()
            }
            
            // Clear old deviceToken field
            record[ChatUser.CodingKeys.deviceToken.rawValue] = nil

            updatedRecords.append(record)
        }

        Logger.info(
            "💾 Updating \(updatedRecords.count) ChatUser records (migrated: \(migrated) tokens)",
            category: .cloudKit)

        try await CloudKitBatchOperations.batchSave(
            records: updatedRecords,
            database: database,
            progress: { completed, total in
                Logger.info(
                    "📈 Migration progress: \(completed)/\(total)",
                    category: .cloudKit)
            },
            savePolicy: .allKeys  // Required to process nil values (clearing old field)
        )

        Logger.info("✅ All ChatUser records migrated successfully!", category: .cloudKit)
    }

    func rollback(database: CKDatabase) async throws {
        Logger.info(
            "⚠️ Rollback v3 → v2: Not supported",
            category: .cloudKit)
        throw MigrationError.rollbackFailed(version: 3, reason: "Cannot restore cleared deviceToken data")
    }

    func validate(database: CKDatabase) async throws -> Bool {
        Logger.info("🔍 Validating if migration v2 → v3 is needed...", category: .cloudKit)

        let query = CKQuery(recordType: ChatUser.recordType, predicate: NSPredicate(value: true))

        do {
            let (records, _) = try await database.records(matching: query, resultsLimit: 10)

            guard !records.isEmpty else {
                return false
            }

            // Check if any records still need migration
            for (_, result) in records {
                let record = try result.get()
                let hasOldDeviceToken = record[ChatUser.CodingKeys.deviceToken.rawValue] != nil
                let hasNewDeviceTokens = record[ChatUser.CodingKeys.deviceTokens.rawValue] != nil

                // Migration needed if:
                // 1. Old deviceToken field still has data, OR
                // 2. New deviceTokens field doesn't exist yet
                if hasOldDeviceToken || !hasNewDeviceTokens {
                    Logger.info("⚠️ Migration needed (oldToken: \(hasOldDeviceToken), newTokens: \(hasNewDeviceTokens))", category: .cloudKit)
                    return true
                }
            }

            Logger.info("✅ All records already migrated", category: .cloudKit)
            return false

        } catch {
            return false
        }
    }
}