import CloudKit
import Foundation

/**
 Migration: Version 2 to Version 3 (EXAMPLE/TEMPLATE - NOT ACTIVE)

 ## Purpose
 This is an EXAMPLE migration demonstrating the RENAME FIELD pattern.
 It is NOT registered in MigrationManifest and will NOT run.
 Use this as a template when you need to rename a field.

 ## Pattern: Field Rename
 Demonstrates how to rename a field while maintaining backwards compatibility.

 ## Example Change
 - Rename ChatRoom.createdBy → ChatRoom.ownerId

 ## Strategy
 1. Add new field (ownerId) while keeping old field (createdBy)
 2. Copy data from old field to new field for all records
 3. Both fields exist temporarily for backwards compatibility
 4. In a future version, remove the old field

 ## Implementation Steps
 1. Update model to include BOTH old and new fields
 2. Implement this migration to copy data
 3. Deploy to all users
 4. In next version, update model to only use new field
 5. Create another migration to remove old field (optional)

 ## Notes
 - CloudKit doesn't have true "rename" operation
 - This requires keeping both fields temporarily
 - Old app versions can still use old field name
 - New app versions use new field name
 */
class Migration_v2_to_v3_EXAMPLE: CloudKitMigration {
    let fromVersion = 2
    let toVersion = 3
    let description = "Example: Rename ChatRoom.createdBy to ownerId"

    func migrate(database: CKDatabase) async throws {
        Logger.info("Starting EXAMPLE migration v2 → v3: Rename field", category: .cloudKit)

        // Fetch all ChatRoom records
        let records = try await CloudKitBatchOperations.batchFetch(
            recordType: ChatRoom.recordType,
            predicate: NSPredicate(value: true),
            database: database
        )

        Logger.info("Found \(records.count) ChatRoom records", category: .cloudKit)

        var updatedRecords: [CKRecord] = []

        for record in records {
            // Copy value from old field to new field
            if let createdBy = record["createdBy"] as? String {
                record["ownerId"] = createdBy
                // Keep old field for backwards compatibility
                // record["createdBy"] remains unchanged
                updatedRecords.append(record)
            }
        }

        // Batch save
        if !updatedRecords.isEmpty {
            try await CloudKitBatchOperations.batchSave(
                records: updatedRecords,
                database: database,
                progress: { completed, total in
                    Logger.debug(
                        "Rename migration progress: \(completed)/\(total)",
                        category: .cloudKit)
                }
            )
        }

        Logger.info("EXAMPLE Migration v2 → v3 completed", category: .cloudKit)
    }

    func rollback(database: CKDatabase) async throws {
        Logger.info("Rolling back EXAMPLE migration v3 → v2", category: .cloudKit)

        // Remove the new field (ownerId)
        let records = try await CloudKitBatchOperations.batchFetch(
            recordType: ChatRoom.recordType,
            predicate: NSPredicate(value: true),
            database: database
        )

        var updatedRecords: [CKRecord] = []
        for record in records {
            record["ownerId"] = nil
            updatedRecords.append(record)
        }

        try await CloudKitBatchOperations.batchSave(
            records: updatedRecords,
            database: database
        )

        Logger.info("Rollback completed", category: .cloudKit)
    }

    func validate(database: CKDatabase) async throws -> Bool {
        let query = CKQuery(
            recordType: ChatRoom.recordType,
            predicate: NSPredicate(value: true)
        )
        let (records, _) = try await database.records(matching: query, resultsLimit: 10)

        for (_, result) in records {
            let record = try result.get()
            // Migration needed if ownerId field is missing but createdBy exists
            if record["ownerId"] == nil && record["createdBy"] != nil {
                return true
            }
        }

        return false
    }
}
