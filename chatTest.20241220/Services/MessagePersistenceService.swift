import Foundation

/// Handles all disk persistence operations for messages and rooms
/// Single Responsibility: Disk I/O only
@MainActor
final class MessagePersistenceService {
    static let shared = MessagePersistenceService()

    private init() {}
    private let fileManager = FileManager.default
    private let maxCachedMessagesPerRoom = 120
    private let maintenanceInterval = 8
    private var writesSinceMaintenance = 0

    // MARK: - File Path Helpers

    private func getDocumentsDirectory() -> URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func roomsFileURL() -> URL {
        getDocumentsDirectory().appendingPathComponent("cached_rooms.json")
    }

    private func messagesFileURL(for roomId: String) -> URL {
        getDocumentsDirectory().appendingPathComponent("cached_messages_\(roomId).json")
    }

    private func unreadCountsFileURL() -> URL {
        getDocumentsDirectory().appendingPathComponent("unread_counts.json")
    }

    private func assetsDirectoryURL() -> URL {
        getDocumentsDirectory().appendingPathComponent("ChatAssets", isDirectory: true)
    }

    // MARK: - Room Persistence

    func saveRooms(_ rooms: [ChatRoom]) async {
        do {
            let data = try JSONEncoder().encode(rooms)
            try data.write(to: roomsFileURL())
            print("💾 MessagePersistenceService: Saved \(rooms.count) rooms to disk")
        } catch {
            print("❌ MessagePersistenceService: Failed to save rooms: \(error)")
        }
    }

    func loadRooms() -> [ChatRoom] {
        do {
            let data = try Data(contentsOf: roomsFileURL())
            let loadedRooms = try JSONDecoder().decode([ChatRoom].self, from: data)
            print("📂 MessagePersistenceService: Loaded \(loadedRooms.count) rooms from disk")
            return loadedRooms
        } catch {
            print("⚠️ MessagePersistenceService: No cached rooms found or decode failed")
            return []
        }
    }

    // MARK: - Message Persistence

    func saveMessages(_ messages: [ChatMessage], for roomId: String) async {
        do {
            // Keep only the latest N messages per room to prevent unbounded growth.
            let trimmedMessages: [ChatMessage]
            if messages.count > maxCachedMessagesPerRoom {
                trimmedMessages = Array(messages.suffix(maxCachedMessagesPerRoom))
            } else {
                trimmedMessages = messages
            }

            let data = try JSONEncoder().encode(trimmedMessages)
            try data.write(to: messagesFileURL(for: roomId))
            print("💾 MessagePersistenceService: Saved \(trimmedMessages.count) messages for room \(roomId)")

            writesSinceMaintenance += 1
            if writesSinceMaintenance >= maintenanceInterval {
                writesSinceMaintenance = 0
                await runStorageMaintenance(validRoomIds: discoverValidRoomIds())
            }
        } catch {
            print("❌ MessagePersistenceService: Failed to save messages: \(error)")
        }
    }

    func loadMessages(for roomId: String) -> [ChatMessage] {
        do {
            let data = try Data(contentsOf: messagesFileURL(for: roomId))
            let loadedMessages = try JSONDecoder().decode([ChatMessage].self, from: data)
            print("📂 MessagePersistenceService: Loaded \(loadedMessages.count) messages for room \(roomId)")
            return loadedMessages
        } catch {
            print("⚠️ MessagePersistenceService: No cached messages found for room \(roomId)")
            return []
        }
    }

    // MARK: - Unread Counts Persistence

    func saveUnreadCounts(_ counts: [String: Int]) async {
        do {
            let data = try JSONEncoder().encode(counts)
            try data.write(to: unreadCountsFileURL())
            print("💾 MessagePersistenceService: Saved unread counts to disk")
        } catch {
            print("❌ MessagePersistenceService: Failed to save unread counts: \(error)")
        }
    }

    func loadUnreadCounts() -> [String: Int] {
        do {
            let data = try Data(contentsOf: unreadCountsFileURL())
            let loadedCounts = try JSONDecoder().decode([String: Int].self, from: data)
            print("📂 MessagePersistenceService: Loaded unread counts from disk")
            return loadedCounts
        } catch {
            print("⚠️ MessagePersistenceService: No cached unread counts found")
            return [:]
        }
    }

    // MARK: - Cleanup

    func deleteMessageCache(for roomId: String) async {
        do {
            try fileManager.removeItem(at: messagesFileURL(for: roomId))
            print("🧹 MessagePersistenceService: Deleted cached messages for room \(roomId)")
        } catch {
            // Ignore if file doesn't exist.
        }
    }

    func runStorageMaintenance(validRoomIds: Set<String>) async {
        removeStaleRoomMessageCaches(validRoomIds: validRoomIds)

        let referencedAssetFileNames = collectReferencedAssetFileNames(validRoomIds: validRoomIds)
        removeOrphanedAssets(keepingFileNames: referencedAssetFileNames)
        removeLooseMediaFilesOutsideAssets(keepingFileNames: referencedAssetFileNames)
    }

    private func discoverValidRoomIds() -> Set<String> {
        var validRoomIds = Set(loadRooms().map { $0.id })
        guard let contents = try? fileManager.contentsOfDirectory(
            at: getDocumentsDirectory(),
            includingPropertiesForKeys: nil
        ) else { return validRoomIds }

        for file in contents {
            let name = file.lastPathComponent
            guard name.hasPrefix("cached_messages_"), name.hasSuffix(".json") else { continue }
            let roomId = name
                .replacingOccurrences(of: "cached_messages_", with: "")
                .replacingOccurrences(of: ".json", with: "")
            if !roomId.isEmpty {
                validRoomIds.insert(roomId)
            }
        }
        return validRoomIds
    }

    private func removeStaleRoomMessageCaches(validRoomIds: Set<String>) {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: getDocumentsDirectory(),
            includingPropertiesForKeys: nil
        ) else { return }

        for file in contents {
            let name = file.lastPathComponent
            guard name.hasPrefix("cached_messages_"), name.hasSuffix(".json") else { continue }

            let roomId = name
                .replacingOccurrences(of: "cached_messages_", with: "")
                .replacingOccurrences(of: ".json", with: "")

            guard !validRoomIds.contains(roomId) else { continue }
            try? fileManager.removeItem(at: file)
        }
    }

    private func collectReferencedAssetFileNames(validRoomIds: Set<String>) -> Set<String> {
        var referenced = Set<String>()

        let rooms = loadRooms()
        for room in rooms where validRoomIds.contains(room.id) {
            if let fileName = room.avatarURL?.lastPathComponent, !fileName.isEmpty {
                referenced.insert(fileName)
            }
        }

        for roomId in validRoomIds {
            let messages = loadMessages(for: roomId)
            for message in messages {
                if let fileName = message.assetURL?.lastPathComponent, !fileName.isEmpty {
                    referenced.insert(fileName)
                }
            }
        }

        return referenced
    }

    private func removeOrphanedAssets(keepingFileNames: Set<String>) {
        let assetsDirectory = assetsDirectoryURL()
        guard let files = try? fileManager.contentsOfDirectory(
            at: assetsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for file in files {
            let fileName = file.lastPathComponent
            guard !keepingFileNames.contains(fileName) else { continue }
            try? fileManager.removeItem(at: file)
        }
    }

    private func removeLooseMediaFilesOutsideAssets(keepingFileNames: Set<String>) {
        guard let files = try? fileManager.contentsOfDirectory(
            at: getDocumentsDirectory(),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        let mediaExtensions = Set(["m4a", "mp3", "wav", "aac", "mov", "mp4", "jpg", "jpeg", "png"])

        for file in files {
            let fileName = file.lastPathComponent
            let fileExtension = file.pathExtension.lowercased()

            guard mediaExtensions.contains(fileExtension) else { continue }
            guard !keepingFileNames.contains(fileName) else { continue }

            // Limit deletion to temp-style UUID media filenames created by this app.
            let baseName = file.deletingPathExtension().lastPathComponent
            guard UUID(uuidString: baseName) != nil else { continue }

            try? fileManager.removeItem(at: file)
        }
    }
}
