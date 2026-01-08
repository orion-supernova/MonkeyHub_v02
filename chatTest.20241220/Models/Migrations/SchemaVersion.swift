import CloudKit
import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// Represents the schema version metadata stored in CloudKit
///
/// This model tracks the current schema version and maintains a history
/// of all completed migrations for auditing and debugging purposes.
struct SchemaVersion {
    static let recordType = "SchemaVersion"
    static let recordName = "CurrentSchemaVersion"

    /// Current schema version number
    let version: Int

    /// JSON-encoded array of migration history entries
    let migrationHistory: String

    /// Timestamp of the last successful migration
    let lastMigrationDate: Date

    /// App version that performed the last migration
    let appVersion: String

    /// Device identifier for debugging (anonymized)
    let deviceIdentifier: String

    /// CloudKit record keys
    private enum CodingKeys: String {
        case version
        case migrationHistory
        case lastMigrationDate
        case appVersion
        case deviceIdentifier
    }

    /// Initialize from CloudKit record
    init(from record: CKRecord) throws {
        guard let version = record[CodingKeys.version.rawValue] as? Int else {
            throw CloudKitError.invalidRecord
        }

        self.version = version
        self.migrationHistory =
            record[CodingKeys.migrationHistory.rawValue] as? String ?? "[]"
        self.lastMigrationDate =
            record[CodingKeys.lastMigrationDate.rawValue] as? Date ?? Date()
        self.appVersion = record[CodingKeys.appVersion.rawValue] as? String ?? "Unknown"
        self.deviceIdentifier =
            record[CodingKeys.deviceIdentifier.rawValue] as? String ?? "Unknown"
    }

    /// Initialize with explicit values
    init(
        version: Int,
        migrationHistory: String = "[]",
        lastMigrationDate: Date = Date(),
        appVersion: String,
        deviceIdentifier: String
    ) {
        self.version = version
        self.migrationHistory = migrationHistory
        self.lastMigrationDate = lastMigrationDate
        self.appVersion = appVersion
        self.deviceIdentifier = deviceIdentifier
    }

    /// Convert to CloudKit record
    func toRecord() -> CKRecord {
        let recordID = CKRecord.ID(recordName: Self.recordName)
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)

        record[CodingKeys.version.rawValue] = version
        record[CodingKeys.migrationHistory.rawValue] = migrationHistory
        record[CodingKeys.lastMigrationDate.rawValue] = lastMigrationDate
        record[CodingKeys.appVersion.rawValue] = appVersion
        record[CodingKeys.deviceIdentifier.rawValue] = deviceIdentifier

        return record
    }

    /// Add a migration entry to the history
    func addingMigration(from: Int, to: Int, description: String) -> SchemaVersion {
        var history = parseMigrationHistory()

        let entry = MigrationHistoryEntry(
            fromVersion: from,
            toVersion: to,
            description: description,
            date: Date(),
            appVersion: currentAppVersion()
        )

        history.append(entry)

        let newHistoryJSON: String
        if let data = try? JSONEncoder().encode(history),
            let json = String(data: data, encoding: .utf8)
        {
            newHistoryJSON = json
        } else {
            newHistoryJSON = migrationHistory
        }

        return SchemaVersion(
            version: to,
            migrationHistory: newHistoryJSON,
            lastMigrationDate: Date(),
            appVersion: currentAppVersion(),
            deviceIdentifier: anonymizedDeviceIdentifier()
        )
    }

    /// Parse migration history from JSON
    func parseMigrationHistory() -> [MigrationHistoryEntry] {
        guard let data = migrationHistory.data(using: .utf8),
            let entries = try? JSONDecoder().decode(
                [MigrationHistoryEntry].self, from: data)
        else {
            return []
        }
        return entries
    }

    /// Get current app version
    private func currentAppVersion() -> String {
        let version =
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        return "\(version) (\(build))"
    }

    /// Get anonymized device identifier (persistent across app launches)
    private func anonymizedDeviceIdentifier() -> String {
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
}

/// Represents a single entry in the migration history
struct MigrationHistoryEntry: Codable {
    let fromVersion: Int
    let toVersion: Int
    let description: String
    let date: Date
    let appVersion: String
}
