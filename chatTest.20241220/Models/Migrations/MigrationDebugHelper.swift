import CloudKit
import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// Debug helper for testing migrations
///
/// ⚠️ FOR TESTING ONLY - DO NOT USE IN PRODUCTION
struct MigrationDebugHelper {

    /// Force migration to run by resetting schema version to v1 and cleaning up v2 fields
    ///
    /// This will:
    /// 1. Reset schema version to v1
    /// 2. Remove bio fields from all ChatUser records (simulating pre-v2 state)
    static func resetSchemaVersionToV1(database: CKDatabase) async throws {
        Logger.info("⚠️ DEBUG: Resetting schema version to v1 and cleaning up v2 fields", category: .cloudKit)

        // Step 1: Reset SchemaVersion record to v1
        let recordID = CKRecord.ID(recordName: SchemaVersion.recordName)

        do {
            // Try to fetch existing record
            let existingRecord = try await database.record(for: recordID)

            // Update to version 1
            existingRecord["version"] = 1
            existingRecord["migrationHistory"] = "[]"
            existingRecord["lastMigrationDate"] = Date()

            _ = try await database.modifyRecords(saving: [existingRecord], deleting: [])

            Logger.info("✅ Schema version reset to v1", category: .cloudKit)

        } catch let error as CKError where error.code == .unknownItem {
            // No record exists, create one at v1
            let newRecord = CKRecord(recordType: SchemaVersion.recordType, recordID: recordID)
            newRecord["version"] = 1
            newRecord["migrationHistory"] = "[]"
            newRecord["lastMigrationDate"] = Date()
            newRecord["appVersion"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"

            #if os(iOS) || os(tvOS)
            if let uuid = UIDevice.current.identifierForVendor?.uuidString {
                newRecord["deviceIdentifier"] = String(uuid.prefix(8))
            } else {
                newRecord["deviceIdentifier"] = "Device-Unknown"
            }
            #else
            newRecord["deviceIdentifier"] = "Device-\(UUID().uuidString.prefix(8))"
            #endif

            _ = try await database.modifyRecords(saving: [newRecord], deleting: [])

            Logger.info("✅ Schema version created at v1", category: .cloudKit)
        }

        // Step 2: Remove bio fields from all ChatUser records
        Logger.info("⚠️ DEBUG: Removing bio fields from ChatUser records", category: .cloudKit)

        do {
            let records = try await CloudKitBatchOperations.batchFetch(
                recordType: ChatUser.recordType,
                predicate: NSPredicate(value: true),
                database: database
            )

            Logger.info("📊 Found \(records.count) ChatUser records to clean", category: .cloudKit)

            // NUCLEAR OPTION: Delete and recreate records without bio field
            var newRecords: [CKRecord] = []
            var recordIDsToDelete: [CKRecord.ID] = []

            for oldRecord in records {
                let userId = oldRecord[ChatUser.CodingKeys.id.rawValue] ?? "unknown"
                Logger.info("🗑️ Will delete and recreate record: \(userId)", category: .cloudKit)

                // Create a completely NEW record with the same ID
                let newRecord = CKRecord(
                    recordType: ChatUser.recordType,
                    recordID: oldRecord.recordID
                )

                // Copy only the fields we want to keep (NO bio!)
                newRecord[ChatUser.CodingKeys.id.rawValue] = oldRecord[ChatUser.CodingKeys.id.rawValue]
                newRecord[ChatUser.CodingKeys.name.rawValue] = oldRecord[ChatUser.CodingKeys.name.rawValue]
                newRecord[ChatUser.CodingKeys.email.rawValue] = oldRecord[ChatUser.CodingKeys.email.rawValue]
                newRecord[ChatUser.CodingKeys.username.rawValue] = oldRecord[ChatUser.CodingKeys.username.rawValue]
                newRecord[ChatUser.CodingKeys.avatar.rawValue] = oldRecord[ChatUser.CodingKeys.avatar.rawValue]
                // Intentionally NOT copying bio field

                newRecords.append(newRecord)
                recordIDsToDelete.append(oldRecord.recordID)
            }

            // Step 1: Delete old records
            Logger.info("💥 Deleting \(recordIDsToDelete.count) old records", category: .cloudKit)
            try await CloudKitBatchOperations.batchDelete(
                recordIDs: recordIDsToDelete,
                database: database
            )

            // Step 2: Create new records without bio
            Logger.info("✨ Creating \(newRecords.count) new records (without bio)", category: .cloudKit)
            try await CloudKitBatchOperations.batchSave(
                records: newRecords,
                database: database,
                savePolicy: .allKeys
            )

            Logger.info("✅ Records recreated without bio field", category: .cloudKit)

        } catch {
            Logger.info("⚠️ Failed to clean bio fields (this is OK if no records exist): \(error)", category: .cloudKit)
        }

        Logger.info("✅ Complete: Reset to v1 with clean data - migrations will run on next launch", category: .cloudKit)
    }

    /// Delete the SchemaVersion record entirely
    ///
    /// This simulates a fresh installation
    static func deleteSchemaVersion(database: CKDatabase) async throws {
        Logger.info("⚠️ DEBUG: Deleting SchemaVersion record", category: .cloudKit)

        let recordID = CKRecord.ID(recordName: SchemaVersion.recordName)

        do {
            try await database.deleteRecord(withID: recordID)
            Logger.info("✅ SchemaVersion deleted - next launch will be like fresh install", category: .cloudKit)
        } catch let error as CKError where error.code == .unknownItem {
            Logger.info("ℹ️ SchemaVersion doesn't exist - already in fresh state", category: .cloudKit)
        }
    }

    /// View current schema version and migration history
    static func printSchemaVersion(database: CKDatabase) async throws {
        Logger.info("🔍 Fetching current schema version...", category: .cloudKit)

        let recordID = CKRecord.ID(recordName: SchemaVersion.recordName)

        do {
            let record = try await database.record(for: recordID)
            let schemaVersion = try SchemaVersion(from: record)

            Logger.info("""
            📋 Current Schema Info:
               Version: \(schemaVersion.version)
               Last Migration: \(schemaVersion.lastMigrationDate)
               App Version: \(schemaVersion.appVersion)
               Device ID: \(schemaVersion.deviceIdentifier)
            """, category: .cloudKit)

            let history = schemaVersion.parseMigrationHistory()
            if !history.isEmpty {
                Logger.info("📜 Migration History:", category: .cloudKit)
                for entry in history {
                    Logger.info(
                        "   v\(entry.fromVersion) → v\(entry.toVersion): \(entry.description) (\(entry.date))",
                        category: .cloudKit)
                }
            } else {
                Logger.info("📜 No migration history", category: .cloudKit)
            }

        } catch let error as CKError where error.code == .unknownItem {
            Logger.info("ℹ️ No SchemaVersion record found - fresh installation", category: .cloudKit)
        }
    }

    /// Check what fields exist on ChatUser records
    static func inspectChatUserFields(database: CKDatabase) async throws {
        Logger.info("🔍 Inspecting ChatUser records...", category: .cloudKit)

        let query = CKQuery(recordType: ChatUser.recordType, predicate: NSPredicate(value: true))
        let (records, _) = try await database.records(matching: query, resultsLimit: 5)

        guard !records.isEmpty else {
            Logger.info("ℹ️ No ChatUser records found", category: .cloudKit)
            return
        }

        for (index, (_, result)) in records.enumerated() {
            let record = try result.get()
            let userId = record[ChatUser.CodingKeys.id.rawValue] as? String ?? "unknown"
            let hasUsername = record[ChatUser.CodingKeys.username.rawValue] != nil
            let hasBio = record[ChatUser.CodingKeys.bio.rawValue] != nil

            Logger.info("""
            👤 User \(index + 1): \(userId)
               - username field: \(hasUsername ? "✅" : "❌")
               - bio field: \(hasBio ? "✅" : "❌")
            """, category: .cloudKit)
        }
    }
}

// MARK: - Usage Examples

/**
 To test migrations, add this code temporarily to your app:

 ```swift
 // In CloudKitManager.initialize() or wherever appropriate:

 #if DEBUG
 // Option 1: Reset to v1 to force migrations
 try? await MigrationDebugHelper.resetSchemaVersionToV1(database: database)

 // Option 2: Check current state
 try? await MigrationDebugHelper.printSchemaVersion(database: database)

 // Option 3: Inspect user fields
 try? await MigrationDebugHelper.inspectChatUserFields(database: database)
 #endif
 ```

 Remember to remove debug code before production release!
 */
