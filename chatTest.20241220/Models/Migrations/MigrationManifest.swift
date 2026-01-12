import Foundation

/// Central registry of all CloudKit schema migrations
///
/// The manifest maintains a list of all available migrations and provides
/// functionality to calculate migration paths between versions.
///
/// To add a new migration:
/// 1. Create a new class implementing CloudKitMigration
/// 2. Register it in the init() method below
/// 3. Migrations are automatically sorted by version
class MigrationManifest {

    /// Shared singleton instance
    static let shared = MigrationManifest()

    /// Dictionary mapping target version to migration
    private var migrations: [Int: CloudKitMigration] = [:]

    /// Current target schema version (highest registered migration)
    var currentSchemaVersion: Int {
        migrations.keys.max() ?? 1
    }

    private init() {
        // Register all migrations here
        // Add new migrations below in sequential order
        register(Migration_v1_to_v2())
        register(Migration_v2_to_v3())

        Logger.info(
            "MigrationManifest initialized with \(migrations.count) migrations", category: .cloudKit
        )
    }

    /// Register a migration in the manifest
    ///
    /// - Parameter migration: The migration to register
    func register(_ migration: CloudKitMigration) {
        migrations[migration.toVersion] = migration
        Logger.debug(
            "Registered migration: v\(migration.fromVersion) → v\(migration.toVersion)",
            category: .cloudKit)
    }

    /// Get the sequence of migrations needed to go from one version to another
    ///
    /// - Parameters:
    ///   - from: Starting schema version
    ///   - to: Target schema version
    /// - Returns: Array of migrations to execute in order
    func getMigrationPath(from: Int, to: Int) -> [CloudKitMigration] {
        var path: [CloudKitMigration] = []
        var current = from

        while current < to {
            let nextVersion = current + 1
            guard let migration = migrations[nextVersion] else {
                Logger.error(
                    "No migration found for v\(current) → v\(nextVersion)", category: .cloudKit)
                break
            }

            path.append(migration)
            current = migration.toVersion
        }

        Logger.debug(
            "Migration path from v\(from) to v\(to): \(path.map { "v\($0.fromVersion)→v\($0.toVersion)" }.joined(separator: ", "))",
            category: .cloudKit)

        return path
    }

    /// Get migration by target version
    ///
    /// - Parameter version: The target version
    /// - Returns: The migration that transitions to this version, or nil
    func getMigration(toVersion version: Int) -> CloudKitMigration? {
        return migrations[version]
    }

    /// Check if a migration exists for the given version transition
    ///
    /// - Parameters:
    ///   - from: Starting version
    ///   - to: Target version
    /// - Returns: true if a migration path exists
    func hasMigrationPath(from: Int, to: Int) -> Bool {
        let path = getMigrationPath(from: from, to: to)
        return !path.isEmpty && path.last?.toVersion == to
    }

    /// Get all registered migrations sorted by version
    var allMigrations: [CloudKitMigration] {
        migrations.values.sorted { $0.toVersion < $1.toVersion }
    }
}