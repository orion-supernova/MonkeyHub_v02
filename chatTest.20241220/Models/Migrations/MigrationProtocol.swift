import CloudKit
import Foundation

/// Protocol defining the contract for CloudKit schema migrations
///
/// Each migration handles the transformation from one schema version to the next.
/// Migrations must be idempotent and handle partial failures gracefully.
protocol CloudKitMigration {
    /// The schema version this migration starts from
    var fromVersion: Int { get }

    /// The schema version this migration transitions to
    var toVersion: Int { get }

    /// Human-readable description of what this migration does
    var description: String { get }

    /// Execute the forward migration
    ///
    /// This function should:
    /// - Fetch all affected records
    /// - Transform the data
    /// - Batch save changes using CloudKitBatchOperations
    /// - Log progress and errors
    ///
    /// - Parameter database: The CloudKit database to operate on
    /// - Throws: MigrationError or CloudKitError if migration fails
    func migrate(database: CKDatabase) async throws

    /// Rollback the migration (best effort)
    ///
    /// This function should attempt to undo the changes made by migrate().
    /// Note: Not all migrations can be rolled back (e.g., data transformations).
    ///
    /// - Parameter database: The CloudKit database to operate on
    /// - Throws: MigrationError if rollback fails
    func rollback(database: CKDatabase) async throws

    /// Validate whether this migration needs to be applied
    ///
    /// This function should check a sample of records to determine if the
    /// migration has already been applied or still needs to run.
    ///
    /// - Parameter database: The CloudKit database to check
    /// - Returns: true if migration is needed, false if already applied
    /// - Throws: CloudKitError if validation check fails
    func validate(database: CKDatabase) async throws -> Bool
}

/// Errors that can occur during migration
enum MigrationError: LocalizedError {
    case noMigrationsAvailable
    case migrationAlreadyInProgress
    case migrationFailed(version: Int, reason: String)
    case rollbackFailed(version: Int, reason: String)
    case validationFailed(version: Int, reason: String)
    case incompatibleVersion(current: Int, target: Int)
    case partialMigration(completed: [Int], failed: Int)
    case migrationLockAcquisitionFailed

    var errorDescription: String? {
        switch self {
        case .noMigrationsAvailable:
            return "No migrations are registered in the system"
        case .migrationAlreadyInProgress:
            return "A migration is already in progress on another device"
        case .migrationFailed(let version, let reason):
            return "Migration to version \(version) failed: \(reason)"
        case .rollbackFailed(let version, let reason):
            return "Rollback from version \(version) failed: \(reason)"
        case .validationFailed(let version, let reason):
            return "Migration validation failed for version \(version): \(reason)"
        case .incompatibleVersion(let current, let target):
            return "Cannot migrate from version \(current) to \(target). Missing intermediate migrations."
        case .partialMigration(let completed, let failed):
            return "Partial migration completed. Succeeded: \(completed.map(String.init).joined(separator: ", ")). Failed at version: \(failed)"
        case .migrationLockAcquisitionFailed:
            return "Could not acquire migration lock. Another migration may be in progress."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .migrationAlreadyInProgress:
            return "Wait for the other device to complete the migration, then restart the app."
        case .migrationFailed, .partialMigration:
            return "Please try restarting the app. If the problem persists, contact support."
        case .incompatibleVersion:
            return "Update your app to the latest version."
        case .rollbackFailed:
            return "Manual intervention may be required. Contact support."
        default:
            return "Restart the app and try again."
        }
    }
}
