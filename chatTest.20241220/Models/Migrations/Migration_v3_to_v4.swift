import CloudKit
import Foundation

/**
 Migration: Version 3 to Version 4 (EXAMPLE/TEMPLATE - NOT ACTIVE)

 ## Purpose
 This is an EXAMPLE migration demonstrating the TYPE CHANGE pattern.
 It is NOT registered in MigrationManifest and will NOT run.
 Use this as a template when you need to change a field's type.

 ## Pattern: Field Type Change
 Demonstrates how to change a field's type while preserving data.

 ## Example Change
 - Convert ChatRoom.messageLifetime from TimeInterval (Double) to Int (seconds)

 ## Strategy
 1. Create new field with new type (messageLifetimeSeconds: Int)
 2. Migrate data from old field to new field with conversion
 3. Keep both fields temporarily for backwards compatibility
 4. In future version, remove old field and update model

 ## Implementation Steps
 1. Update model to include BOTH old and new fields
 2. Implement this migration to convert and copy data
 3. Deploy to all users
 4. In next version, update model to only use new field
 5. Create another migration to remove old field (optional)

 ## Notes
 - CloudKit doesn't support in-place type changes
 - Requires creating a new field with different name
 - Data conversion happens during migration
 - Ensure conversion logic handles edge cases (nil, negative values, etc.)
 */
class Migration_v3_to_v4_EXAMPLE: CloudKitMigration {
    let fromVersion = 3
    let toVersion = 4
    let description = "Example: Convert messageLifetime from TimeInterval to Int"

    func migrate(database: CKDatabase) async throws {
        Logger.info("Starting EXAMPLE migration v3 → v4: Type conversion", category: .cloudKit)

        // Fetch all ChatRoom records that have messageLifetime set
        let predicate = NSPredicate(format: "messageLifetime != nil")
        let records = try await CloudKitBatchOperations.batchFetch(
            recordType: ChatRoom.recordType,
            predicate: predicate,
            database: database
        )

        Logger.info(
            "Found \(records.count) ChatRoom records with messageLifetime",
            category: .cloudKit)

        var updatedRecords: [CKRecord] = []

        for record in records {
            // Convert TimeInterval (Double) to Int (seconds)
            if let lifetime = record["messageLifetime"] as? Double {
                // Round to nearest second
                let lifetimeSeconds = Int(lifetime)

                // Store in new field
                record["messageLifetimeSeconds"] = lifetimeSeconds

                // Keep old field for backwards compatibility
                // record["messageLifetime"] remains unchanged

                updatedRecords.append(record)

                Logger.debug(
                    "Converting messageLifetime \(lifetime)s → \(lifetimeSeconds)s for room: \(record["id"] ?? "unknown")",
                    category: .cloudKit)
            }
        }

        // Batch save
        if !updatedRecords.isEmpty {
            try await CloudKitBatchOperations.batchSave(
                records: updatedRecords,
                database: database,
                progress: { completed, total in
                    Logger.debug(
                        "Type conversion progress: \(completed)/\(total)",
                        category: .cloudKit)
                }
            )
        }

        Logger.info("EXAMPLE Migration v3 → v4 completed", category: .cloudKit)
    }

    func rollback(database: CKDatabase) async throws {
        Logger.info("Rolling back EXAMPLE migration v4 → v3", category: .cloudKit)

        // Remove new Int field
        let predicate = NSPredicate(format: "messageLifetimeSeconds != nil")
        let records = try await CloudKitBatchOperations.batchFetch(
            recordType: ChatRoom.recordType,
            predicate: predicate,
            database: database
        )

        var updatedRecords: [CKRecord] = []
        for record in records {
            record["messageLifetimeSeconds"] = nil
            updatedRecords.append(record)
        }

        try await CloudKitBatchOperations.batchSave(
            records: updatedRecords,
            database: database
        )

        Logger.info("Rollback completed", category: .cloudKit)
    }

    func validate(database: CKDatabase) async throws -> Bool {
        let predicate = NSPredicate(format: "messageLifetime != nil")
        let query = CKQuery(recordType: ChatRoom.recordType, predicate: predicate)
        let (records, _) = try await database.records(matching: query, resultsLimit: 10)

        for (_, result) in records {
            let record = try result.get()
            // Migration needed if messageLifetimeSeconds is missing
            // but messageLifetime exists
            if record["messageLifetimeSeconds"] == nil {
                return true
            }
        }

        return false
    }
}

/**
 ## Additional Type Change Examples

 ### String to Enum
 ```swift
 // Old: status: String ("active", "inactive", "pending")
 // New: status: Int (0, 1, 2) - enum cases

 if let statusString = record["status"] as? String {
     let statusEnum: Int
     switch statusString {
     case "active": statusEnum = 0
     case "inactive": statusEnum = 1
     case "pending": statusEnum = 2
     default: statusEnum = 0
     }
     record["statusCode"] = statusEnum
 }
 ```

 ### Date to Timestamp
 ```swift
 // Old: createdAt: Date
 // New: createdAtTimestamp: Int64 (Unix timestamp)

 if let date = record["createdAt"] as? Date {
     let timestamp = Int64(date.timeIntervalSince1970)
     record["createdAtTimestamp"] = timestamp
 }
 ```

 ### String Array to JSON String
 ```swift
 // Old: tags: [String]
 // New: tagsJSON: String (JSON array)

 if let tags = record["tags"] as? [String] {
     if let jsonData = try? JSONEncoder().encode(tags),
        let jsonString = String(data: jsonData, encoding: .utf8) {
         record["tagsJSON"] = jsonString
     }
 }
 ```
 */
