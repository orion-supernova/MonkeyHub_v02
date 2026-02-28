//
//  DataMigrationManager.swift
//  chatTest.20241220
//
//  Created for handling data migration between environments
//

import Foundation
import CloudKit

enum DataMigrationError: LocalizedError {
    case noDataToExport
    case exportFailed(String)
    case importFailed(String)
    case noUserLoggedIn
    case cloudKitNotAvailable

    var errorDescription: String? {
        switch self {
        case .noDataToExport:
            return "No cached data found to export"
        case .exportFailed(let reason):
            return "Export failed: \(reason)"
        case .importFailed(let reason):
            return "Import failed: \(reason)"
        case .noUserLoggedIn:
            return "No user is currently logged in"
        case .cloudKitNotAvailable:
            return "CloudKit is not available"
        }
    }
}

struct MigrationData: Codable {
    let userId: String
    let rooms: [ExportedRoom]
    let messages: [String: [ExportedMessage]] // roomId -> messages
    let exportDate: Date
    let appVersion: String

    struct ExportedRoom: Codable {
        let id: String
        let name: String
        let createdBy: String
        let createdAt: Date
        let lastMessage: String?
        let lastMessageDate: Date?
        let participants: [String]
        let description: String?
        let isPrivate: Bool?
        let type: String
        let messageLifetime: TimeInterval?
    }

    struct ExportedMessage: Codable {
        let id: String
        let senderId: String
        let senderName: String
        let content: String
        let type: String
        let timestamp: Date
        let roomId: String
        let assetURL: String?
        let status: String
    }
}

class DataMigrationManager: ObservableObject {
    static let shared = DataMigrationManager()

    @Published var isExporting = false
    @Published var isImporting = false
    @Published var progress: Double = 0
    @Published var statusMessage = ""

    private let persistenceService = MessagePersistenceService.shared
    private let cloudKitManager = CloudKitManager.shared
    private let fileManager = FileManager.default

    private init() {}

    // Date formatting for CloudKit (matches CloudKitManager's format)
    private func formatDateForCloudKit(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    // MARK: - Export Data from CloudKit

    @MainActor
    func exportDataToDisk() async throws -> URL {
        isExporting = true
        progress = 0
        statusMessage = "Fetching data from CloudKit..."

        // Get user ID
        guard let userId = UserDefaults.standard.string(forKey: "userId") else {
            throw DataMigrationError.noUserLoggedIn
        }

        progress = 0.1
        statusMessage = "Fetching all rooms from CloudKit..."

        // Fetch ALL rooms from CloudKit (not cached data)
        let rooms = try await cloudKitManager.fetchChatRooms()
        print("📦 Fetched \(rooms.count) rooms from CloudKit:")
        for room in rooms {
            print("  - \(room.name) (ID: \(room.id))")
        }

        if rooms.isEmpty {
            print("⚠️ WARNING: No rooms found in CloudKit! Export will be empty.")
        }

        progress = 0.3
        statusMessage = "Fetching ALL messages from CloudKit (this may take a while)..."

        // Fetch ALL messages for all rooms from CloudKit using the migration-specific function
        var allMessages: [String: [MigrationData.ExportedMessage]] = [:]
        let totalRooms = rooms.count
        for (index, room) in rooms.enumerated() {
            // Use fetchAllMessages to get COMPLETE history for migration
            let messages = try await cloudKitManager.fetchAllMessages(for: room.id)
            let exportedMessages = messages.map { msg in
                MigrationData.ExportedMessage(
                    id: msg.id,
                    senderId: msg.senderId,
                    senderName: msg.senderName,
                    content: msg.content,
                    type: msg.type.rawValue,
                    timestamp: msg.timestamp,
                    roomId: msg.roomId,
                    assetURL: msg.assetURL?.absoluteString,
                    status: msg.status.rawValue
                )
            }
            allMessages[room.id] = exportedMessages

            // Update progress
            let roomProgress = 0.3 + (0.4 * Double(index + 1) / Double(totalRooms))
            await MainActor.run {
                progress = roomProgress
                statusMessage = "Fetching ALL messages for room \(index + 1)/\(totalRooms) (\(messages.count) messages)..."
            }
        }

        progress = 0.6
        statusMessage = "Preparing export..."

        // Create migration data
        let exportedRooms = rooms.map { room in
            MigrationData.ExportedRoom(
                id: room.id,
                name: room.name,
                createdBy: room.createdBy,
                createdAt: room.createdAt,
                lastMessage: room.lastMessage,
                lastMessageDate: room.lastMessageDate,
                participants: room.participants,
                description: room.description,
                isPrivate: room.isPrivate,
                type: room.type.rawValue,
                messageLifetime: room.messageLifetime
            )
        }

        print("📦 Export Summary:")
        print("  - Rooms: \(exportedRooms.count)")
        print("  - Total messages: \(allMessages.values.map { $0.count }.reduce(0, +))")
        for (roomId, messages) in allMessages {
            let roomName = rooms.first(where: { $0.id == roomId })?.name ?? "Unknown"
            print("    - \(roomName): \(messages.count) messages")
        }

        progress = 0.8
        statusMessage = "Writing export file..."

        // Write to file and bundle assets
        // Prepare export directory
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let baseName = "migration_export_\(Int(Date().timeIntervalSince1970))"
        let exportDir = documentsPath.appendingPathComponent(baseName, isDirectory: true)
        let assetsDir = exportDir.appendingPathComponent("Assets", isDirectory: true)

        try? fileManager.removeItem(at: exportDir)
        try fileManager.createDirectory(at: assetsDir, withIntermediateDirectories: true)

        // Prepare JSON encoder
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        // Rebuild messages with local asset references and copy files
        var messagesWithAssets: [String: [MigrationData.ExportedMessage]] = [:]
        for (roomId, messages) in allMessages {
            var updated: [MigrationData.ExportedMessage] = []
            for var m in messages {
                if let assetURLString = m.assetURL, let originalURL = URL(string: assetURLString) {
                    let ext = originalURL.pathExtension.isEmpty ? "dat" : originalURL.pathExtension
                    let fileName = "\(m.id).\(ext)"
                    let destURL = assetsDir.appendingPathComponent(fileName)
                    if fileManager.fileExists(atPath: originalURL.path) {
                        try? fileManager.removeItem(at: destURL)
                        do {
                            try fileManager.copyItem(at: originalURL, to: destURL)
                            print("📦 Copied asset for message \(m.id) to \(destURL.lastPathComponent) (")
                            if let values = try? destURL.resourceValues(forKeys: [.fileSizeKey]), let size = values.fileSize {
                                let formatter = ByteCountFormatter(); formatter.countStyle = .file
                                print("   size: \(formatter.string(fromByteCount: Int64(size)))")
                            }
                        } catch {
                            print("❌ Failed to copy asset for message \(m.id): \(error)")
                        }
                        m = MigrationData.ExportedMessage(
                            id: m.id,
                            senderId: m.senderId,
                            senderName: m.senderName,
                            content: m.content,
                            type: m.type,
                            timestamp: m.timestamp,
                            roomId: m.roomId,
//                            assetURL: "Assets/\(fileName)",
                            assetURL: "\(fileName)",
                            status: m.status
                        )
                    } else {
                        print("⚠️ Asset source not found for message \(m.id) at: \(originalURL.path)")
                    }
                }
                updated.append(m)
            }
            messagesWithAssets[roomId] = updated
        }

        let migrationData = MigrationData(
            userId: userId,
            rooms: exportedRooms,
            messages: messagesWithAssets,
            exportDate: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        )

        // Write primary JSON inside the export directory
        let data = try encoder.encode(migrationData)
        let dataJSON = exportDir.appendingPathComponent("data.json")
        try data.write(to: dataJSON)

        // Also write a thin compatibility JSON at the root to satisfy UI scanning pattern
        let rootJSON = documentsPath.appendingPathComponent("\(baseName).json")
        try data.write(to: rootJSON)

        // Verify assets directory content
        if let files = try? fileManager.contentsOfDirectory(at: assetsDir, includingPropertiesForKeys: [.fileSizeKey]) {
            let totalBytes = files.compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }.reduce(0, +)
            let fmt = ByteCountFormatter(); fmt.countStyle = .file
            print("📦 Assets bundled: \(files.count) files, total \(fmt.string(fromByteCount: Int64(totalBytes)))")
        } else {
            print("ℹ️ No assets directory or failed to read assets directory")
        }

        progress = 1.0
        statusMessage = "Export completed!"
        isExporting = false

        // Return the root JSON path so the existing UI can find it
        return rootJSON
    }

    // MARK: - Delete All CloudKit Data

    private func deleteAllCloudKitData() async throws {
        print("🗑️ Starting CloudKit deletion...")

        // Fetch all existing rooms
        let allRooms = try await cloudKitManager.fetchChatRooms()
        print("🗑️ Found \(allRooms.count) existing rooms to delete")

        if allRooms.isEmpty {
            print("✅ No existing data to delete")
            return
        }

        // Delete all messages first (to avoid orphans)
        print("🗑️ Deleting messages from \(allRooms.count) rooms...")
        var totalMessagesDeleted = 0

        for (index, room) in allRooms.enumerated() {
            print("🗑️ Fetching messages for room \(index + 1)/\(allRooms.count): \(room.name)")
            let messages = try await cloudKitManager.fetchAllMessages(for: room.id)

            if !messages.isEmpty {
                // Delete in batches of 400 (CloudKit limit)
                let messageIds = messages.map { CKRecord.ID(recordName: $0.id) }
                for batchStart in stride(from: 0, to: messageIds.count, by: 400) {
                    let batchEnd = min(batchStart + 400, messageIds.count)
                    let batch = Array(messageIds[batchStart..<batchEnd])

                    _ = try await cloudKitManager.database.modifyRecords(saving: [], deleting: batch)
                    print("🗑️ Deleted batch of \(batch.count) messages")
                }
                totalMessagesDeleted += messages.count
                print("🗑️ Deleted \(messages.count) messages from room: \(room.name)")
            }
        }

        print("🗑️ Total messages deleted: \(totalMessagesDeleted)")

        // Delete all rooms in batches
        print("🗑️ Deleting \(allRooms.count) rooms from CloudKit...")
        let roomIds = allRooms.map { CKRecord.ID(recordName: $0.id) }

        for batchStart in stride(from: 0, to: roomIds.count, by: 400) {
            let batchEnd = min(batchStart + 400, roomIds.count)
            let batch = Array(roomIds[batchStart..<batchEnd])

            _ = try await cloudKitManager.database.modifyRecords(saving: [], deleting: batch)
            print("🗑️ Deleted batch of \(batch.count) rooms")
        }

        print("✅ CloudKit deletion complete: \(allRooms.count) rooms, \(totalMessagesDeleted) messages deleted")
    }

    // MARK: - Import Data to CloudKit

    func importDataToCloudKit(fromFile url: URL) async throws {
        await MainActor.run {
            isImporting = true
            progress = 0
            statusMessage = "Reading import file..."
        }

        // Read file
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let migrationData = try decoder.decode(MigrationData.self, from: data)

        let fileManager = FileManager.default

        print("📥 Import file loaded:")
        print("  - Export date: \(migrationData.exportDate)")
        print("  - User ID: \(migrationData.userId)")
        print("  - Rooms in file: \(migrationData.rooms.count)")
        print("  - Total messages in file: \(migrationData.messages.values.map { $0.count }.reduce(0, +))")

        if migrationData.rooms.isEmpty {
            print("❌ ERROR: Import file contains NO ROOMS!")
            throw DataMigrationError.noDataToExport
        }

        for room in migrationData.rooms {
            let messageCount = migrationData.messages[room.id]?.count ?? 0
            print("  - Room: \(room.name) (\(messageCount) messages)")
        }

        // Determine assets directory (sibling folder to the json file)
        let exportFolder = url.deletingPathExtension()
        let assetsDir = exportFolder.appendingPathComponent("Assets", isDirectory: true)

        var assetsAvailable = false
        if fileManager.fileExists(atPath: assetsDir.path) {
            if let files = try? fileManager.contentsOfDirectory(at: assetsDir, includingPropertiesForKeys: [.fileSizeKey]) {
                let total = files.count
                let bytes = files.compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }.reduce(0, +)
                let fmt = ByteCountFormatter(); fmt.countStyle = .file
                print("📥 Found Assets dir with \(total) files (\(fmt.string(fromByteCount: Int64(bytes)))) at: \(assetsDir.path)")
                assetsAvailable = total > 0
            }
        } else {
            print("ℹ️ No Assets directory next to import file at: \(assetsDir.path)")
        }

        await MainActor.run {
            progress = 0.05
            statusMessage = "Verifying CloudKit access..."
        }

        // Verify user is logged in
        guard let currentUserId = UserDefaults.standard.string(forKey: "userId") else {
            throw DataMigrationError.noUserLoggedIn
        }

        await MainActor.run {
            progress = 0.1
            statusMessage = "Deleting existing data from CloudKit..."
        }

        // Clear existing data before importing (full replacement)
        try await deleteAllCloudKitData()

        await MainActor.run {
            progress = 0.2
            statusMessage = "Uploading rooms..."
        }

        // Create a nonisolated upload context
        let cloudKit = cloudKitManager

        // Upload rooms - build records matching CloudKit schema exactly
        let totalRooms = migrationData.rooms.count
        print("📤 Starting upload of \(totalRooms) rooms...")

        for (index, exportedRoom) in migrationData.rooms.enumerated() {
            do {
                let record = CKRecord(recordType: ChatRoom.recordType, recordID: CKRecord.ID(recordName: exportedRoom.id))

                // String fields
                record[ChatRoom.idKey] = exportedRoom.id as CKRecordValue
                record[ChatRoom.nameKey] = exportedRoom.name as CKRecordValue
                record[ChatRoom.createdByKey] = exportedRoom.createdBy as CKRecordValue
                record[ChatRoom.typeKey] = exportedRoom.type as CKRecordValue

                // createdAt as STRING (ISO8601)
                record[ChatRoom.createdAtKey] = formatDateForCloudKit(exportedRoom.createdAt) as CKRecordValue

                // lastMessage as String (optional)
                if let lastMessage = exportedRoom.lastMessage {
                    record[ChatRoom.lastMessageKey] = lastMessage as CKRecordValue
                }

                // lastMessageDate as Date & Time (not string!)
                if let lastMessageDate = exportedRoom.lastMessageDate {
                    record[ChatRoom.lastMessageDateKey] = lastMessageDate as CKRecordValue
                }

                // participants as String List
                record[ChatRoom.participantsKey] = exportedRoom.participants as CKRecordValue

                // Optional fields
                if let description = exportedRoom.description {
                    record[ChatRoom.descriptionKey] = description as CKRecordValue
                }

                // isPrivate as Int(64) - CloudKit stores bool as 0/1
                record[ChatRoom.isPrivateKey] = (exportedRoom.isPrivate ?? false ? 1 : 0) as CKRecordValue

                // messageLifetime as Double (optional)
                if let messageLifetime = exportedRoom.messageLifetime {
                    record[ChatRoom.messageLifetimeKey] = messageLifetime as CKRecordValue
                }

                print("📤 Uploading room \(index + 1)/\(totalRooms): \(exportedRoom.name)")

                // Save the room
                let savedRecord = try await cloudKit.database.save(record)
                print("✅ Successfully uploaded room: \(exportedRoom.name) (ID: \(savedRecord.recordID.recordName))")

                let roomProgress = 0.2 + (0.3 * Double(index + 1) / Double(totalRooms))
                await MainActor.run {
                    progress = roomProgress
                    statusMessage = "Uploading room \(index + 1)/\(totalRooms): \(exportedRoom.name)..."
                }
            } catch {
                print("❌ Failed to import room \(exportedRoom.id) '\(exportedRoom.name)': \(error)")
                throw DataMigrationError.importFailed("Failed to upload room '\(exportedRoom.name)': \(error.localizedDescription)")
            }
        }

        print("✅ Successfully uploaded all \(totalRooms) rooms")

        await MainActor.run {
            progress = 0.5
            statusMessage = "Uploading messages..."
        }

        // Upload messages in batches using CKModifyRecordsOperation to ensure assets are attached reliably
        let totalMessages = migrationData.messages.values.flatMap { $0 }.count
        var uploadedMessages = 0
        let batchSize = 200

        // Flatten messages preserving order
        let flatMessages: [MigrationData.ExportedMessage] = migrationData.messages.values.flatMap { $0 }

        for batchStart in stride(from: 0, to: flatMessages.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, flatMessages.count)
            let batch = Array(flatMessages[batchStart..<batchEnd])

            // Build records for this batch
            var records: [CKRecord] = []
            var tempFiles: [URL] = [] // Keep strong references to temp files for the duration of the operation

            for message in batch {
                let messageType = MessageType(rawValue: message.type) ?? .text
                let record = CKRecord(recordType: ChatMessage.recordType, recordID: CKRecord.ID(recordName: message.id))
                record[ChatMessage.idKey] = message.id
                record[ChatMessage.senderIdKey] = message.senderId
                record[ChatMessage.senderNameKey] = message.senderName
                record[ChatMessage.contentKey] = message.content
                record[ChatMessage.typeKey] = messageType.rawValue
                record[ChatMessage.timestampKey] = message.timestamp
                record[ChatMessage.roomIdKey] = message.roomId

                // Resolve asset path (relative inside bundle or absolute)
                let resolvedAssetURL: URL? = {
                    guard let path = message.assetURL else { return nil }
                    if path.hasPrefix("http://") || path.hasPrefix("https://") || path.hasPrefix("file://") {
                        return URL(string: path)
                    } else {
                        return assetsDir.appendingPathComponent(path)
                    }
                }()

                if let sourceURL = resolvedAssetURL, fileManager.fileExists(atPath: sourceURL.path) {
                    // Copy to a unique temporary file for CKAsset reliability
                    let ext = sourceURL.pathExtension.isEmpty ? "dat" : sourceURL.pathExtension
                    let tmpURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(ext)
                    do {
                        try? FileManager.default.removeItem(at: tmpURL)
                        try FileManager.default.copyItem(at: sourceURL, to: tmpURL)
                        record[ChatMessage.assetKey] = CKAsset(fileURL: tmpURL)
                        tempFiles.append(tmpURL)
                        print("📤 Prepared asset for message \(message.id): \(tmpURL.lastPathComponent)")
                    } catch {
                        print("⚠️ Failed to stage asset for message \(message.id): \(error)")
                    }
                } else if let badURL = resolvedAssetURL {
                    print("⚠️ Asset file missing for message \(message.id) at: \(badURL.path)")
                }

                records.append(record)
            }

            // Perform modify operation for this batch
            let op = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
            op.savePolicy = .allKeys
            op.qualityOfService = .userInitiated
            op.perRecordCompletionBlock = { record, error in
                if let error = error {
                    print("❌ Failed to save message record \(record.recordID.recordName): \(error)")
                } else {
                    uploadedMessages += 1
                    let messageProgress = 0.5 + (0.5 * Double(uploadedMessages) / Double(totalMessages))
                    Task { @MainActor in
                        self.progress = messageProgress
                        self.statusMessage = "Uploading message \(uploadedMessages)/\(totalMessages)..."
                    }
                }
            }
            op.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    print("✅ Batch saved: records \(batchStart+1)-\(batchEnd) of \(flatMessages.count)")
                case .failure(let error):
                    print("❌ Batch save failed: \(error)")
                }
                for tmp in tempFiles {
                    try? FileManager.default.removeItem(at: tmp)
                }
            }

            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                op.completionBlock = { continuation.resume() }
                cloudKit.database.add(op)
            }
        }

        // Automatic post-import asset rehydration
        await rehydrateAssets(fromFile: url)

        await MainActor.run {
            progress = 1.0
            statusMessage = "Import completed!"
            isImporting = false
        }
    }

    // MARK: - Post-Import Asset Rehydration
    private func rehydrateAssets(fromFile url: URL) async {
        print("🔁 Starting asset rehydration pass...")
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let migrationData = try decoder.decode(MigrationData.self, from: data)

            let exportFolder = url.deletingPathExtension()
            let assetsDir = exportFolder.appendingPathComponent("Assets", isDirectory: true)
            let fm = FileManager.default
            guard fm.fileExists(atPath: assetsDir.path) else {
                print("ℹ️ Rehydrate: No Assets directory found at \(assetsDir.path)")
                return
            }

            // Flatten messages that reference an asset path
            let messagesWithAssets: [MigrationData.ExportedMessage] = migrationData.messages.values
                .flatMap { $0 }
                .filter { $0.assetURL != nil }

            if messagesWithAssets.isEmpty {
                print("ℹ️ Rehydrate: No messages with asset references in JSON")
                return
            }

            let batchSize = 200
            let db = cloudKitManager.database

            for start in stride(from: 0, to: messagesWithAssets.count, by: batchSize) {
                let end = min(start + batchSize, messagesWithAssets.count)
                let slice = Array(messagesWithAssets[start..<end])

                // Fetch existing records for these message IDs
                let recordIDs = slice.map { CKRecord.ID(recordName: $0.id) }
                var fetched: [CKRecord.ID: CKRecord] = [:]

                // Fetch in a single operation
                let fetchOp = CKFetchRecordsOperation(recordIDs: recordIDs)
                fetchOp.perRecordResultBlock = { recordID, result in
                    switch result {
                    case .success(let record):
                        fetched[recordID] = record
                    case .failure(let error):
                        print("⚠️ Rehydrate: Failed to fetch record \(recordID.recordName): \(error)")
                    }
                }

                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    fetchOp.completionBlock = { continuation.resume() }
                    db.add(fetchOp)
                }

                // Prepare updates with staged temp files
                var recordsToSave: [CKRecord] = []
                var temps: [URL] = []

                for msg in slice {
                    guard let record = fetched[CKRecord.ID(recordName: msg.id)] else { continue }
                    guard let path = msg.assetURL else { continue }

                    let sourceURL: URL
                    if path.hasPrefix("http://") || path.hasPrefix("https://") || path.hasPrefix("file://") {
                        guard let u = URL(string: path) else { continue }
                        sourceURL = u
                    } else {
                        sourceURL = assetsDir.appendingPathComponent(path)
                    }

                    guard fm.fileExists(atPath: sourceURL.path) else {
                        print("⚠️ Rehydrate: Missing asset file for message \(msg.id) at \(sourceURL.path)")
                        continue
                    }

                    // Stage temp file
                    let ext = sourceURL.pathExtension.isEmpty ? "dat" : sourceURL.pathExtension
                    let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
                    do {
                        try? fm.removeItem(at: tmp)
                        try fm.copyItem(at: sourceURL, to: tmp)
                        record[ChatMessage.assetKey] = CKAsset(fileURL: tmp)
                        temps.append(tmp)
                        recordsToSave.append(record)
                    } catch {
                        print("❌ Rehydrate: Failed to stage asset for \(msg.id): \(error)")
                    }
                }

                guard !recordsToSave.isEmpty else { continue }

                let modify = CKModifyRecordsOperation(recordsToSave: recordsToSave, recordIDsToDelete: nil)
                modify.savePolicy = .changedKeys
                modify.qualityOfService = .userInitiated
                modify.perRecordCompletionBlock = { record, error in
                    if let error = error {
                        print("❌ Rehydrate: Failed to update \(record.recordID.recordName): \(error)")
                    } else {
                        print("✅ Rehydrate: Updated asset for \(record.recordID.recordName)")
                    }
                }
                modify.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        print("✅ Rehydrate: Batch updated (\(start+1)-\(end))")
                    case .failure(let error):
                        print("❌ Rehydrate: Batch failed: \(error)")
                    }
                    for t in temps { try? fm.removeItem(at: t) }
                }

                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    modify.completionBlock = { continuation.resume() }
                    db.add(modify)
                }
            }

            print("🔁 Asset rehydration pass completed.")
        } catch {
            print("❌ Rehydrate: Unexpected error: \(error)")
        }
    }

    // MARK: - Clear All Local Data

    func clearAllLocalData() throws {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]

        // Remove cached files
        let filesToRemove = [
            "cached_rooms.json",
            "unread_counts.json"
        ]

        for fileName in filesToRemove {
            let fileUrl = documentsPath.appendingPathComponent(fileName)
            try? fileManager.removeItem(at: fileUrl)
        }

        // Remove all message cache files
        let contents = try? fileManager.contentsOfDirectory(at: documentsPath, includingPropertiesForKeys: nil)
        let messageCacheFiles = contents?.filter { $0.lastPathComponent.hasPrefix("cached_messages_") } ?? []
        for file in messageCacheFiles {
            try? fileManager.removeItem(at: file)
        }

        // Remove ChatAssets directory
        let assetsPath = documentsPath.appendingPathComponent("ChatAssets")
        try? fileManager.removeItem(at: assetsPath)

        // Clear UserDefaults
        UserDefaults.standard.removeObject(forKey: "userId")
        UserDefaults.standard.removeObject(forKey: "deviceToken")
    }

    // MARK: - Get Disk Usage Stats

    @MainActor
    func getDiskUsageStatsSync() -> (rooms: Int, messages: Int, totalSize: String) {
        // Synchronous version - counts files instead of messages
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        print("📊 Checking disk usage at: \(documentsPath.path)")

        // Count room files
        let roomsFile = documentsPath.appendingPathComponent("cached_rooms.json")
        let roomCount: Int
        if let data = try? Data(contentsOf: roomsFile),
           let rooms = try? JSONDecoder().decode([ChatRoom].self, from: data) {
            roomCount = rooms.count
            print("✅ Found \(roomCount) rooms in cache")
        } else {
            roomCount = 0
            print("⚠️ No cached rooms found")
        }

        // Count message files
        guard let contents = try? fileManager.contentsOfDirectory(at: documentsPath, includingPropertiesForKeys: [.fileSizeKey]) else {
            print("❌ Failed to read documents directory")
            return (roomCount, 0, "0 bytes")
        }

        let messageFiles = contents.filter { $0.lastPathComponent.hasPrefix("cached_messages_") }
        let messageCount = messageFiles.count
        print("✅ Found \(messageCount) message cache files")

        // Calculate total size recursively (includes ChatAssets contents).
        var totalSize: UInt64 = 0
        if let enumerator = fileManager.enumerator(
            at: documentsPath,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                      values.isRegularFile == true
                else { continue }
                totalSize += UInt64(values.fileSize ?? 0)
            }
        }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let sizeString = formatter.string(fromByteCount: Int64(totalSize))
        print("💾 Total cache size: \(sizeString)")

        return (roomCount, messageCount, sizeString)
    }
}
