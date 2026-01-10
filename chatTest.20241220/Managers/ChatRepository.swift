import Foundation
import Combine
import CloudKit
import SwiftUI

/// A robust Single Source of Truth (SSOT) responsible for all Chat Data.
/// Manages the authoritative list of rooms, active messages, and handles incoming push data.
@MainActor
class ChatRepository: ObservableObject {
    static let shared = ChatRepository()

    // MARK: - Published State
    @Published var rooms: [ChatRoom] = []
    @Published var activeRoomMessages: [ChatMessage] = []
    @Published var unreadCounts: [String: Int] = [:]

    // MARK: - Internal Dependencies
    private let cloudKit = CloudKitManager.shared
    private let persistence = MessagePersistenceService.shared
    private let userIdUserDefaultsKey = "userId"
    private var activeRoomId: String?

    private init() {
        rooms = persistence.loadRooms()
    }
    
    // MARK: - Single Source of Truth for Messages

    /// Upserts a message into the active room's message list with deduplication
    /// This is the ONLY method that should modify activeRoomMessages
    /// - Parameters:
    ///   - message: The message to insert or update
    ///   - roomId: The room ID this message belongs to
    ///   - saveToisk: Whether to persist to disk after update
    private func upsertMessage(_ message: ChatMessage, in roomId: String, saveToDisk: Bool = true) {
        guard roomId == activeRoomId else { return }

        // Check if message already exists
        if let existingIndex = activeRoomMessages.firstIndex(where: { $0.id == message.id }) {
            // Update existing message (e.g., status change from pending -> sent)
            activeRoomMessages[existingIndex] = message
            print("🔄 ChatRepository: Updated existing message \(message.id)")
        } else {
            // Insert new message at the beginning (newest first)
            activeRoomMessages.insert(message, at: 0)
            print("➕ ChatRepository: Inserted new message \(message.id)")
        }

        if saveToDisk {
            Task {
                await persistence.saveMessages(activeRoomMessages, for: roomId)
            }
        }
    }

    /// Batch upsert multiple messages (used for fetching from CloudKit)
    private func upsertMessages(_ messages: [ChatMessage], in roomId: String, saveToDisk: Bool = true) {
        guard roomId == activeRoomId else { return }

        for message in messages {
            // Check if message already exists
            if let existingIndex = activeRoomMessages.firstIndex(where: { $0.id == message.id }) {
                activeRoomMessages[existingIndex] = message
            } else {
                // Find correct insertion position to maintain chronological order
                let insertIndex = activeRoomMessages.firstIndex { $0.timestamp < message.timestamp } ?? activeRoomMessages.count
                activeRoomMessages.insert(message, at: insertIndex)
            }
        }

        print("🔄 ChatRepository: Upserted \(messages.count) messages")

        if saveToDisk {
            Task {
                await persistence.saveMessages(activeRoomMessages, for: roomId)
            }
        }
    }


    // MARK: - Room Management
    
    func fetchRooms() async {
        do {
            let fetchedRooms = try await cloudKit.fetchChatRooms()
            self.rooms = fetchedRooms
            Task {
                await persistence.saveRooms(fetchedRooms)
            }
            print("✅ ChatRepository: Fetched \(fetchedRooms.count) rooms")
        } catch {
            print("❌ ChatRepository: Failed to fetch rooms: \(error)")
        }
    }

    func setActiveRoom(_ roomId: String?) {
        self.activeRoomId = roomId
        if let roomId = roomId {
            // Clear unread count
            unreadCounts[roomId] = 0
            // Load cached messages immediately
            let cachedMessages = persistence.loadMessages(for: roomId)
            self.activeRoomMessages = cachedMessages
        } else {
            // Exiting a room
            self.activeRoomMessages = []
        }
    }
    
    // MARK: - Message Management
    
    func fetchMessages(for roomId: String) async {
        guard roomId == activeRoomId else { return }

        do {
            let messages = try await cloudKit.fetchRecentMessages(for: roomId, limit: 30)
            if self.activeRoomId == roomId {
                // Preserve pending messages
                let pendingMessages = self.activeRoomMessages.filter { $0.status == .pending }

                // Clear and re-populate with fetched messages (limit to newest batch + pending)
                self.activeRoomMessages = []

                withAnimation {
                    upsertMessages(messages, in: roomId, saveToDisk: false)

                    // Re-add pending messages
                    for pending in pendingMessages {
                        if !self.activeRoomMessages.contains(where: { $0.id == pending.id }) {
                            upsertMessage(pending, in: roomId, saveToDisk: false)
                        }
                    }
                }

                await persistence.saveMessages(activeRoomMessages, for: roomId)
            }
        } catch {
            print("❌ ChatRepository: Failed to fetch messages for room \(roomId): \(error)")
        }
    }

    func fetchOlderMessages(for roomId: String) async {
        guard roomId == activeRoomId, !activeRoomMessages.isEmpty else { return }

        // Get the oldest message timestamp (messages are sorted newest first)
        let oldestMessage = activeRoomMessages.last { $0.status != .pending }
        guard let oldestDate = oldestMessage?.timestamp else { return }

        print("📡 ChatRepository: Fetching messages before \(oldestDate)")

        do {
            let olderMessages = try await cloudKit.fetchRecentMessages(for: roomId, before: oldestDate, limit: 30)
            guard !olderMessages.isEmpty else { 
                print("🏁 ChatRepository: No older messages found")
                return 
            }

            if self.activeRoomId == roomId {
                withAnimation {
                    upsertMessages(olderMessages, in: roomId, saveToDisk: true)
                }
            }
        } catch {
            print("❌ ChatRepository: Failed to fetch older messages for room \(roomId): \(error)")
        }
    }
    
    func sendMessage(_ message: ChatMessage) async {
        // Optimistic update: Add message as pending
        var pendingMessage = message
        pendingMessage.status = .pending

        withAnimation {
            upsertMessage(pendingMessage, in: message.roomId)
        }

        // Use CloudKit manager to actually send
        do {
            try await cloudKit.sendMessage(message)

            // Success: Update status to sent
            var sentMessage = message
            sentMessage.status = .sent
            withAnimation {
                upsertMessage(sentMessage, in: message.roomId)
            }

            // Update the room's last message locally too
            updateLocalRoom(for: message)
        } catch {
            print("❌ ChatRepository: Failed to send message: \(error)")
            // Error: Update status
            var errorMessage = message
            errorMessage.status = .error
            withAnimation {
                upsertMessage(errorMessage, in: message.roomId)
            }
        }
    }
    
    // MARK: - Notification Handling (Data Pipeline)

    /// Called by AppDelegate when a remote notification allows us to process data.
    /// Deduplication is handled by AppDelegate before calling this.
    func handleIncomingNotification(_ userInfo: [AnyHashable: Any]) {
        guard let cloudKitNotification = CKNotification(fromRemoteNotificationDictionary: userInfo) as? CKQueryNotification,
              let recordFields = cloudKitNotification.recordFields,
              let roomId = recordFields[ChatMessage.roomIdKey] as? String,
              let recordID = cloudKitNotification.recordID
        else { return }

        print("📥 ChatRepository: Processing incoming message for Room \(roomId)")

        // Extract data for room update
        let content = recordFields[ChatMessage.contentKey] as? String ?? "New Message"
        let senderId = recordFields[ChatMessage.senderIdKey] as? String ?? "unknown"
        let timestamp = Date() // Approximate

        // 1. Update Room List (Lobby)
        if let index = rooms.firstIndex(where: { $0.id == roomId }) {
            var updatedRoom = rooms[index]
            updatedRoom.lastMessage = content
            updatedRoom.lastMessageDate = timestamp

            withAnimation {
                rooms[index] = updatedRoom
                // Move to top
                let r = rooms.remove(at: index)
                rooms.insert(r, at: 0)
            }

            Task {
                await persistence.saveRooms(rooms)
            }

            // Increment unread count if not active room and not from me
            let currentUserId = UserDefaults.standard.string(forKey: userIdUserDefaultsKey) ?? ""
            if activeRoomId != roomId && senderId != currentUserId {
                unreadCounts[roomId, default: 0] += 1
            }
        } else {
            // New room? Fetch all rooms to discover it
            Task { await fetchRooms() }
        }

        // 2. Update Active Room Messages (if valid)
        // CRITICAL FIX: Fetch the full message from CloudKit instead of reconstructing
        if activeRoomId == roomId {
            Task {
                do {
                    // Fetch the complete message record from CloudKit
                    let record = try await cloudKit.database.record(for: recordID)
                    let fullMessage = try ChatMessage(from: record)

                    await MainActor.run {
                        withAnimation {
                            // Use upsertMessage for proper deduplication
                            upsertMessage(fullMessage, in: roomId)
                        }
                    }

                    print("✅ ChatRepository: Fetched and inserted full message with type: \(fullMessage.type)")
                } catch {
                    print("❌ ChatRepository: Failed to fetch full message from CloudKit: \(error)")
                    // Fallback: Use reconstructed message from notification payload
                    let senderName = recordFields[ChatMessage.senderNameKey] as? String ?? "Unknown"
                    let typeRaw = recordFields[ChatMessage.typeKey] as? String ?? "text"
                    let messageType = MessageType(rawValue: typeRaw) ?? .text

                    let fallbackMessage = ChatMessage(
                        id: recordID.recordName,
                        senderId: senderId,
                        senderName: senderName,
                        content: content,
                        type: messageType,
                        timestamp: timestamp,
                        roomId: roomId,
                        assetURL: nil  // Asset URL not available in notification payload
                    )

                    await MainActor.run {
                        withAnimation {
                            upsertMessage(fallbackMessage, in: roomId)
                        }
                    }

                    print("⚠️ ChatRepository: Using fallback message with type: \(messageType)")
                }
            }
        }
    }
    
    private func updateLocalRoom(for message: ChatMessage) {
        if let index = rooms.firstIndex(where: { $0.id == message.roomId }) {
            var updatedRoom = rooms[index]
            updatedRoom.lastMessage = message.content
            updatedRoom.lastMessageDate = message.timestamp

            withAnimation {
                rooms[index] = updatedRoom
                let r = rooms.remove(at: index)
                rooms.insert(r, at: 0)
            }

            Task {
                await persistence.saveRooms(rooms)
            }
        }
    }
    
    func deleteMessage(_ messageId: String, in roomId: String) async {
        // Optimistic UI update
        if roomId == activeRoomId {
            withAnimation {
                activeRoomMessages.removeAll { $0.id == messageId }
            }

            Task {
                await persistence.saveMessages(activeRoomMessages, for: roomId)
            }
        }

        do {
            try await cloudKit.deleteChatMessage(messageId)
            print("✅ ChatRepository: Deleted message \(messageId)")
        } catch {
            print("❌ ChatRepository: Failed to delete message: \(error)")
            // Revert optimism? Would need to fetch again to be safe.
            if roomId == activeRoomId {
               await fetchMessages(for: roomId)
            }
        }
    }
}
