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
    private let userIdUserDefaultsKey = "userId"
    private var activeRoomId: String?
    
    private init() {}
    
    // MARK: - Room Management
    
    func fetchRooms() async {
        do {
            let fetchedRooms = try await cloudKit.fetchChatRooms()
            self.rooms = fetchedRooms
            print("✅ ChatRepository: Fetched \(fetchedRooms.count) rooms")
        } catch {
            print("❌ ChatRepository: Failed to fetch rooms: \(error)")
        }
    }
    
    func setActiveRoom(_ roomId: String?) {
        self.activeRoomId = roomId
        if let roomId = roomId {
            // Check for unread marker clearing could go here
            unreadCounts[roomId] = 0
            // Load messages for this room
            Task { await fetchMessages(for: roomId) }
        } else {
            // Exiting a room
            self.activeRoomMessages = []
        }
    }
    
    // MARK: - Message Management
    
    func fetchMessages(for roomId: String) async {
        guard roomId == activeRoomId else { return }
        
        do {
            let messages = try await cloudKit.fetchMessages(for: roomId)
            if self.activeRoomId == roomId {
                 self.activeRoomMessages = messages
            }
        } catch {
            print("❌ ChatRepository: Failed to fetch messages for room \(roomId): \(error)")
        }
    }
    
    func sendMessage(_ message: ChatMessage) async {
        // Optimistic update
        var pendingMessage = message
        pendingMessage.status = .pending
        
        if message.roomId == activeRoomId {
            withAnimation {
                activeRoomMessages.insert(pendingMessage, at: 0)
            }
        }
        
        // Use CloudKit manager to actually send
        do {
            try await cloudKit.sendMessage(message)
            
            // Success: Update status to sent
            if let index = activeRoomMessages.firstIndex(where: { $0.id == message.id }) {
                withAnimation {
                    activeRoomMessages[index].status = .sent
                }
            }
            
            // Update the room's last message locally too
            updateLocalRoom(for: message)
        } catch {
            print("❌ ChatRepository: Failed to send message: \(error)")
            // Error: Update status
            if let index = activeRoomMessages.firstIndex(where: { $0.id == message.id }) {
                withAnimation {
                    activeRoomMessages[index].status = .error
                }
            }
        }
    }
    
    // MARK: - Notification Handling (Data Pipeline)
    
    /// Called by AppDelegate when a remote notification allows us to process data.
    /// Deduplication is handled by AppDelegate before calling this.
    func handleIncomingNotification(_ userInfo: [AnyHashable: Any]) {
        guard let cloudKitNotification = CKNotification(fromRemoteNotificationDictionary: userInfo) as? CKQueryNotification,
              let recordFields = cloudKitNotification.recordFields,
              let roomId = recordFields[ChatMessage.roomIdKey] as? String
        else { return }
        
        print("📥 ChatRepository: Processing incoming message for Room \(roomId)")
        
        // Extract data
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
        if activeRoomId == roomId {
            // Reconstruct message for active view
            let recordID = cloudKitNotification.recordID?.recordName ?? UUID().uuidString
            let senderName = recordFields[ChatMessage.senderNameKey] as? String ?? "Unknown"
            
            let message = ChatMessage(
                id: recordID,
                senderId: senderId,
                senderName: senderName,
                content: content,
                type: .text, // Simplified for notification
                timestamp: timestamp,
                roomId: roomId
            )
            
            withAnimation {
                // Avoid duplicates in the message list
                if !activeRoomMessages.contains(where: { $0.id == recordID }) {
                     activeRoomMessages.insert(message, at: 0)
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
        }
    }
    
    func deleteMessage(_ messageId: String, in roomId: String) async {
        // Optimistic UI update
        if roomId == activeRoomId {
            withAnimation {
                activeRoomMessages.removeAll { $0.id == messageId }
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
