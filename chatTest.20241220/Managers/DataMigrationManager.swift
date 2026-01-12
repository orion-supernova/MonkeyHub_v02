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

        let migrationData = MigrationData(
            userId: userId,
            rooms: exportedRooms,
            messages: allMessages,
            exportDate: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        )

        progress = 0.8
        statusMessage = "Writing export file..."

        // Write to file
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(migrationData)

        // Save to Documents directory
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let exportFileName = "migration_export_\(Date().timeIntervalSince1970).json"
        let exportUrl = documentsPath.appendingPathComponent(exportFileName)

        try data.write(to: exportUrl)

        progress = 1.0
        statusMessage = "Export completed!"
        isExporting = false

        return exportUrl
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

        // Upload messages
        let totalMessages = migrationData.messages.values.flatMap { $0 }.count
        var uploadedMessages = 0

        for (roomId, messages) in migrationData.messages {
            for message in messages {
                do {
                    let messageType = MessageType(rawValue: message.type) ?? .text
                    let messageStatus = MessageStatus(rawValue: message.status) ?? .sent
                    let assetURL = message.assetURL.flatMap { URL(string: $0) }

                    let record = CKRecord(recordType: ChatMessage.recordType, recordID: CKRecord.ID(recordName: message.id))
                    record[ChatMessage.idKey] = message.id
                    record[ChatMessage.senderIdKey] = message.senderId
                    record[ChatMessage.senderNameKey] = message.senderName
                    record[ChatMessage.contentKey] = message.content
                    record[ChatMessage.typeKey] = messageType.rawValue
                    // Convert Date to String for CloudKit (timestamp is stored as String in schema)
                    record[ChatMessage.timestampKey] = formatDateForCloudKit(message.timestamp)
                    record[ChatMessage.roomIdKey] = message.roomId
                    if let assetURL = assetURL {
                        record[ChatMessage.assetKey] = CKAsset(fileURL: assetURL)
                    }

                    // Save the message (no need to check - we already deleted everything)
                    try await cloudKit.database.save(record)

                    uploadedMessages += 1
                    let messageProgress = 0.5 + (0.5 * Double(uploadedMessages) / Double(totalMessages))
                    await MainActor.run {
                        progress = messageProgress
                        statusMessage = "Uploading message \(uploadedMessages)/\(totalMessages)..."
                    }
                } catch {
                    print("Failed to import message \(message.id): \(error)")
                }
            }
        }

        await MainActor.run {
            progress = 1.0
            statusMessage = "Import completed!"
            isImporting = false
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

        // Calculate total size
        var totalSize: UInt64 = 0
        for fileUrl in contents {
            if let size = try? fileUrl.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += UInt64(size)
            }
        }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let sizeString = formatter.string(fromByteCount: Int64(totalSize))
        print("💾 Total cache size: \(sizeString)")

        return (roomCount, messageCount, sizeString)
    }
}
