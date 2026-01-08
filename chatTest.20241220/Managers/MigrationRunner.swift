import CloudKit
import Combine
import Foundation

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Helper Functions

/// Get a persistent device identifier that works across platforms
private func getDeviceIdentifier() -> String {
    #if os(iOS) || os(tvOS)
    if let uuid = UIDevice.current.identifierForVendor?.uuidString {
        return String(uuid.prefix(8))
    }
    #endif

    // Fallback: Use a persistent identifier stored in UserDefaults
    let key = "com.app.deviceIdentifier"
    if let stored = UserDefaults.standard.string(forKey: key) {
        return stored
    }

    // Generate once and persist
    let newId = "Device-\(UUID().uuidString.prefix(8))"
    UserDefaults.standard.set(newId, forKey: key)
    return newId
}

/// Orchestrates the execution of CloudKit schema migrations
///
/// MigrationRunner is responsible for:
/// - Determining which migrations need to run
/// - Executing migrations sequentially
/// - Tracking progress
/// - Rolling back on failure
/// - Preventing concurrent migrations across devices
@MainActor
class MigrationRunner: ObservableObject {

    /// Current migration state
    @Published var state: MigrationState = .notStarted

    /// Progress value (0.0 to 1.0)
    @Published var progress: Double = 0.0

    private let database: CKDatabase
    private let manifest: MigrationManifest

    /// Initialize the migration runner
    ///
    /// - Parameter database: The CloudKit database to operate on
    init(database: CKDatabase, manifest: MigrationManifest = .shared) {
        self.database = database
        self.manifest = manifest
    }

    /// Run all pending migrations to reach the target version
    ///
    /// - Parameter targetVersion: The desired schema version
    /// - Throws: MigrationError if migration fails
    func migrate(to targetVersion: Int) async throws {
        Logger.info("Starting migration to version \(targetVersion)", category: .cloudKit)

        // Check if already running
        guard case .notStarted = state else {
            throw MigrationError.migrationAlreadyInProgress
        }

        // Acquire migration lock
        let lock = MigrationLock(database: database)
        guard try await lock.acquireLock() else {
            throw MigrationError.migrationLockAcquisitionFailed
        }

        defer {
            Task {
                try? await lock.releaseLock()
            }
        }

        do {
            // Fetch current schema version
            let currentVersion = try await fetchCurrentSchemaVersion()
            Logger.info("Current schema version: \(currentVersion)", category: .cloudKit)

            // Validate target version
            guard currentVersion < targetVersion else {
                Logger.info("Already at target version or higher", category: .cloudKit)
                state = .completed
                return
            }

            // Get migration path
            let migrations = manifest.getMigrationPath(from: currentVersion, to: targetVersion)

            guard !migrations.isEmpty else {
                throw MigrationError.noMigrationsAvailable
            }

            Logger.info("Found \(migrations.count) migrations to execute", category: .cloudKit)

            // Execute migrations
            var completedVersions: [Int] = []

            for (index, migration) in migrations.enumerated() {
                let currentStep = index + 1
                let totalSteps = migrations.count

                state = .inProgress(
                    current: currentStep,
                    total: totalSteps,
                    description: migration.description
                )
                progress = Double(currentStep) / Double(totalSteps)

                Logger.info(
                    "Executing migration \(currentStep)/\(totalSteps): v\(migration.fromVersion) → v\(migration.toVersion)",
                    category: .cloudKit)

                do {
                    // Validate migration is needed
                    let needsMigration = try await migration.validate(database: database)

                    if needsMigration {
                        // Execute migration
                        try await migration.migrate(database: database)
                        Logger.info(
                            "Migration v\(migration.fromVersion) → v\(migration.toVersion) completed",
                            category: .cloudKit)
                    } else {
                        Logger.info(
                            "Migration v\(migration.fromVersion) → v\(migration.toVersion) not needed (already applied)",
                            category: .cloudKit)
                    }

                    // Update schema version
                    try await updateSchemaVersion(
                        to: migration.toVersion,
                        migrationDescription: migration.description
                    )

                    completedVersions.append(migration.toVersion)

                } catch {
                    Logger.error(
                        "Migration v\(migration.fromVersion) → v\(migration.toVersion) failed: \(error)",
                        category: .cloudKit)

                    // Attempt rollback
                    Logger.info("Attempting to rollback completed migrations", category: .cloudKit
                    )
                    await rollbackMigrations(migrations: migrations, completedVersions: completedVersions)

                    state = .failed(
                        error: MigrationError.migrationFailed(
                            version: migration.toVersion,
                            reason: error.localizedDescription
                        ))

                    throw MigrationError.partialMigration(
                        completed: completedVersions,
                        failed: migration.toVersion
                    )
                }
            }

            state = .completed
            progress = 1.0
            Logger.info("All migrations completed successfully", category: .cloudKit)

        } catch {
            if case .completed = state {
                // Already handled
            } else {
                state = .failed(error: error)
            }
            throw error
        }
    }

    /// Fetch the current schema version from CloudKit
    private func fetchCurrentSchemaVersion() async throws -> Int {
        let recordID = CKRecord.ID(recordName: SchemaVersion.recordName)

        do {
            let record = try await database.record(for: recordID)
            let schemaVersion = try SchemaVersion(from: record)
            return schemaVersion.version
        } catch let error as CKError where error.code == .unknownItem {
            // Schema version record doesn't exist yet, assume version 1
            Logger.info("No schema version record found, assuming version 1", category: .cloudKit)
            return 1
        } catch {
            Logger.error("Failed to fetch schema version: \(error)", category: .cloudKit)
            throw error
        }
    }

    /// Update the schema version record in CloudKit
    private func updateSchemaVersion(to version: Int, migrationDescription: String) async throws {
        let recordID = CKRecord.ID(recordName: SchemaVersion.recordName)

        // Fetch existing record or create new one
        let recordToSave: CKRecord

        do {
            // Fetch existing record
            let existingRecord = try await database.record(for: recordID)
            let existing = try SchemaVersion(from: existingRecord)

            // Calculate new schema version
            let updatedSchemaVersion = existing.addingMigration(
                from: existing.version,
                to: version,
                description: migrationDescription
            )

            // CRITICAL: Update the EXISTING record's fields (preserves CloudKit metadata)
            existingRecord["version"] = updatedSchemaVersion.version
            existingRecord["migrationHistory"] = updatedSchemaVersion.migrationHistory
            existingRecord["lastMigrationDate"] = updatedSchemaVersion.lastMigrationDate
            existingRecord["appVersion"] = updatedSchemaVersion.appVersion
            existingRecord["deviceIdentifier"] = updatedSchemaVersion.deviceIdentifier

            recordToSave = existingRecord

        } catch let error as CKError where error.code == .unknownItem {
            // Create new schema version record (first time only)
            let schemaVersion = SchemaVersion(
                version: version,
                migrationHistory: "[]",
                lastMigrationDate: Date(),
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                    ?? "Unknown",
                deviceIdentifier: getDeviceIdentifier()
            )

            recordToSave = schemaVersion.toRecord()
        }

        // Save the record
        _ = try await database.modifyRecords(saving: [recordToSave], deleting: [])

        Logger.info("Schema version updated to \(version)", category: .cloudKit)
    }

    /// Rollback completed migrations in reverse order
    private func rollbackMigrations(
        migrations: [CloudKitMigration],
        completedVersions: [Int]
    ) async {
        guard !completedVersions.isEmpty else { return }

        Logger.info(
            "Rolling back \(completedVersions.count) completed migrations", category: .cloudKit)

        for version in completedVersions.reversed() {
            if let migration = migrations.first(where: { $0.toVersion == version }) {
                do {
                    Logger.info(
                        "Rolling back migration v\(migration.fromVersion) → v\(migration.toVersion)",
                        category: .cloudKit)
                    try await migration.rollback(database: database)
                    Logger.info("Rollback successful", category: .cloudKit)
                } catch {
                    Logger.error(
                        "Rollback failed for v\(migration.fromVersion) → v\(migration.toVersion): \(error)",
                        category: .cloudKit)
                }
            }
        }
    }

    /// Reset migration state (for testing)
    func reset() {
        state = .notStarted
        progress = 0.0
    }
}

/// Represents the current state of migration
enum MigrationState {
    case notStarted
    case inProgress(current: Int, total: Int, description: String)
    case completed
    case failed(error: Error)

    var userMessage: String {
        switch self {
        case .notStarted:
            return "Preparing to update app data..."
        case .inProgress(let current, let total, let description):
            return "Updating app data (\(current)/\(total)): \(description)"
        case .completed:
            return "App data updated successfully"
        case .failed(let error):
            return "Data update failed: \(error.localizedDescription)"
        }
    }

    var isInProgress: Bool {
        if case .inProgress = self {
            return true
        }
        return false
    }
}

/// Handles migration locking to prevent concurrent migrations
class MigrationLock {
    private let database: CKDatabase
    private let lockRecordID = CKRecord.ID(recordName: "MigrationLock")
    private var acquiredLock = false

    init(database: CKDatabase) {
        self.database = database
    }

    /// Attempt to acquire the migration lock
    ///
    /// Includes automatic timeout: stale locks (>30 min old) are automatically released
    ///
    /// - Returns: true if lock was acquired, false if already locked
    func acquireLock() async throws -> Bool {
        // First, check if there's an existing lock that's stale
        do {
            let existingRecord = try await database.record(for: lockRecordID)

            // Check if lock is stale (older than 30 minutes)
            if let lockedAt = existingRecord["lockedAt"] as? Date {
                let lockAge = Date().timeIntervalSince(lockedAt)
                let staleLockThreshold: TimeInterval = 30 * 60 // 30 minutes

                if lockAge > staleLockThreshold {
                    // Lock is stale, delete it
                    Logger.info(
                        "Found stale migration lock (age: \(Int(lockAge/60)) min), removing it",
                        category: .cloudKit)
                    try await database.deleteRecord(withID: lockRecordID)
                }
            }
        } catch let error as CKError where error.code == .unknownItem {
            // No existing lock, continue
        }

        // Now try to acquire the lock
        let lockRecord = CKRecord(recordType: "MigrationLock", recordID: lockRecordID)
        lockRecord["lockedBy"] = getDeviceIdentifier()
        lockRecord["lockedAt"] = Date()

        do {
            _ = try await database.modifyRecords(saving: [lockRecord], deleting: [])
            acquiredLock = true
            Logger.info("Migration lock acquired", category: .cloudKit)
            return true
        } catch let error as CKError {
            // If record already exists, lock is held by another device
            if error.code == .serverRecordChanged {
                Logger.info("Migration lock is held by another device", category: .cloudKit)
                return false
            }
            throw error
        }
    }

    /// Release the migration lock
    func releaseLock() async throws {
        guard acquiredLock else { return }

        try await database.deleteRecord(withID: lockRecordID)
        acquiredLock = false
        Logger.info("Migration lock released", category: .cloudKit)
    }
}
