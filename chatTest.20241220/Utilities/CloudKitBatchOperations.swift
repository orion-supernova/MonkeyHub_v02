import CloudKit
import Foundation

/// Utility class for performing batch operations on CloudKit while respecting the 400 record limit
///
/// CloudKit has a limit of 400 records per operation. This class automatically chunks
/// operations and provides retry logic with exponential backoff.
@MainActor
class CloudKitBatchOperations {

    /// Configuration for batch operations
    struct Config {
        static let defaultBatchSize = 400
        static let maxRetryAttempts = 3
        static let initialRetryDelay: TimeInterval = 2.0
    }

    /// Fetch all records matching a query, handling pagination automatically
    ///
    /// - Parameters:
    ///   - recordType: The type of records to fetch
    ///   - predicate: The predicate to filter records
    ///   - database: The CloudKit database to query
    /// - Returns: Array of all matching CKRecord objects
    /// - Throws: CloudKitError if the operation fails
    static func batchFetch(
        recordType: String,
        predicate: NSPredicate,
        database: CKDatabase
    ) async throws -> [CKRecord] {
        Logger.info(
            "Starting batch fetch for recordType: \(recordType)", category: .cloudKit)

        var allRecords: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?

        let query = CKQuery(recordType: recordType, predicate: predicate)

        repeat {
            let (fetchedRecords, nextCursor) = try await fetchPage(
                query: query,
                cursor: cursor,
                database: database
            )

            allRecords.append(contentsOf: fetchedRecords)
            cursor = nextCursor

            Logger.debug(
                "Fetched \(fetchedRecords.count) records, total: \(allRecords.count)",
                category: .cloudKit)

        } while cursor != nil

        Logger.info("Batch fetch completed: \(allRecords.count) records", category: .cloudKit)
        return allRecords
    }

    /// Fetch a single page of records
    private static func fetchPage(
        query: CKQuery? = nil,
        cursor: CKQueryOperation.Cursor?,
        database: CKDatabase
    ) async throws -> ([CKRecord], CKQueryOperation.Cursor?) {
        var attempt = 0

        while attempt < Config.maxRetryAttempts {
            do {
                let results: ([CKRecord], CKQueryOperation.Cursor?)

                if let cursor = cursor {
                    let (recordResults, nextCursor) = try await database.records(
                        continuingMatchFrom: cursor)
                    let records = try recordResults.compactMap { _, result in
                        try result.get()
                    }
                    results = (records, nextCursor)
                } else if let query = query {
                    let (recordResults, nextCursor) = try await database.records(matching: query)
                    let records = try recordResults.compactMap { _, result in
                        try result.get()
                    }
                    results = (records, nextCursor)
                } else {
                    throw CloudKitError.custom("Either query or cursor must be provided")
                }

                return results

            } catch let error as CKError {
                attempt += 1

                if attempt >= Config.maxRetryAttempts {
                    Logger.error(
                        "Batch fetch failed after \(attempt) attempts: \(error)", category: .cloudKit
                    )
                    throw mapCloudKitError(error)
                }

                if shouldRetry(error) {
                    let delay = Config.initialRetryDelay * pow(2.0, Double(attempt - 1))
                    Logger.info(
                        "Batch fetch failed, retrying in \(delay)s (attempt \(attempt)/\(Config.maxRetryAttempts))",
                        category: .cloudKit)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    throw mapCloudKitError(error)
                }
            }
        }

        throw CloudKitError.operationFailed
    }

    /// Save records in batches, respecting the 400 record limit
    ///
    /// - Parameters:
    ///   - records: Array of records to save
    ///   - batchSize: Number of records per batch (default: 400)
    ///   - database: The CloudKit database to save to
    ///   - progress: Optional closure called after each batch with (completed, total)
    ///   - savePolicy: CloudKit save policy (default: .changedKeys for migrations)
    /// - Throws: CloudKitError if any batch fails
    static func batchSave(
        records: [CKRecord],
        batchSize: Int = Config.defaultBatchSize,
        database: CKDatabase,
        progress: ((Int, Int) -> Void)? = nil,
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy = .changedKeys
    ) async throws {
        Logger.info("Starting batch save of \(records.count) records", category: .cloudKit)

        let batches = records.chunked(into: batchSize)
        var completedCount = 0

        for (index, batch) in batches.enumerated() {
            Logger.debug(
                "Saving batch \(index + 1)/\(batches.count) (\(batch.count) records)",
                category: .cloudKit)

            try await saveBatch(batch, database: database, savePolicy: savePolicy)

            completedCount += batch.count
            progress?(completedCount, records.count)

            Logger.debug(
                "Batch \(index + 1) completed. Progress: \(completedCount)/\(records.count)",
                category: .cloudKit)
        }

        Logger.info("Batch save completed: \(records.count) records", category: .cloudKit)
    }

    /// Save a single batch of records with retry logic
    private static func saveBatch(
        _ records: [CKRecord],
        database: CKDatabase,
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy = .changedKeys
    ) async throws {
        var attempt = 0

        while attempt < Config.maxRetryAttempts {
            do {
                // Use CKModifyRecordsOperation for more control over save policy
                let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: [])
                operation.savePolicy = savePolicy
                operation.database = database

                let results = try await database.modifyRecords(saving: records, deleting: [])

                for (_, result) in results.saveResults {
                    _ = try result.get()
                }

                return

            } catch let error as CKError {
                attempt += 1

                if attempt >= Config.maxRetryAttempts {
                    Logger.error(
                        "Batch save failed after \(attempt) attempts: \(error)", category: .cloudKit
                    )
                    throw mapCloudKitError(error)
                }

                if shouldRetry(error) {
                    let delay = Config.initialRetryDelay * pow(2.0, Double(attempt - 1))
                    Logger.info(
                        "Batch save failed, retrying in \(delay)s (attempt \(attempt)/\(Config.maxRetryAttempts))",
                        category: .cloudKit)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    throw mapCloudKitError(error)
                }
            }
        }

        throw CloudKitError.operationFailed
    }

    /// Delete records in batches
    ///
    /// - Parameters:
    ///   - recordIDs: Array of record IDs to delete
    ///   - batchSize: Number of records per batch (default: 400)
    ///   - database: The CloudKit database to delete from
    /// - Throws: CloudKitError if any batch fails
    static func batchDelete(
        recordIDs: [CKRecord.ID],
        batchSize: Int = Config.defaultBatchSize,
        database: CKDatabase
    ) async throws {
        Logger.info("Starting batch delete of \(recordIDs.count) records", category: .cloudKit)

        let batches = recordIDs.chunked(into: batchSize)

        for (index, batch) in batches.enumerated() {
            Logger.debug(
                "Deleting batch \(index + 1)/\(batches.count) (\(batch.count) records)",
                category: .cloudKit)

            try await deleteBatch(batch, database: database)
        }

        Logger.info("Batch delete completed: \(recordIDs.count) records", category: .cloudKit)
    }

    /// Delete a single batch of records with retry logic
    private static func deleteBatch(
        _ recordIDs: [CKRecord.ID],
        database: CKDatabase
    ) async throws {
        var attempt = 0

        while attempt < Config.maxRetryAttempts {
            do {
                _ = try await database.modifyRecords(saving: [], deleting: recordIDs)
                return

            } catch let error as CKError {
                attempt += 1

                if attempt >= Config.maxRetryAttempts {
                    Logger.error(
                        "Batch delete failed after \(attempt) attempts: \(error)",
                        category: .cloudKit)
                    throw mapCloudKitError(error)
                }

                if shouldRetry(error) {
                    let delay = Config.initialRetryDelay * pow(2.0, Double(attempt - 1))
                    Logger.info(
                        "Batch delete failed, retrying in \(delay)s (attempt \(attempt)/\(Config.maxRetryAttempts))",
                        category: .cloudKit)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    throw mapCloudKitError(error)
                }
            }
        }

        throw CloudKitError.operationFailed
    }

    /// Determine if an error is retryable
    private static func shouldRetry(_ error: CKError) -> Bool {
        switch error.code {
        case .networkUnavailable, .networkFailure, .serverResponseLost, .serviceUnavailable,
            .requestRateLimited, .zoneBusy:
            return true
        default:
            return false
        }
    }

    /// Map CKError to CloudKitError
    private static func mapCloudKitError(_ error: CKError) -> CloudKitError {
        switch error.code {
        case .networkUnavailable, .networkFailure, .serverResponseLost:
            return .networkError
        case .notAuthenticated:
            return .notAuthenticated
        case .permissionFailure:
            return .permissionDenied
        default:
            return .unknown(error)
        }
    }
}

/// Extension to chunk arrays into smaller batches
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
