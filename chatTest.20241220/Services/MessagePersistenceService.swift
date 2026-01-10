import Foundation
import CloudKit

/// Handles all disk persistence operations for messages and rooms
/// Single Responsibility: Disk I/O only
@MainActor
final class MessagePersistenceService {
    static let shared = MessagePersistenceService()

    private init() {}

    // MARK: - File Path Helpers

    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func roomsFileURL() -> URL {
        getDocumentsDirectory().appendingPathComponent("cached_rooms.json")
    }

    private func messagesFileURL(for roomId: String) -> URL {
        getDocumentsDirectory().appendingPathComponent("cached_messages_\(roomId).json")
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
            let data = try JSONEncoder().encode(messages)
            try data.write(to: messagesFileURL(for: roomId))
            print("💾 MessagePersistenceService: Saved \(messages.count) messages for room \(roomId)")
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
}
