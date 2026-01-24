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
    
    // MARK: - Deduplication (Single Source of Truth)
    // The Repository is the ONLY place that deduplicates messages
    private var processedMessageIds = Set<String>() // Track processed message IDs to prevent duplicates
    private let maxProcessedIdsCache = 1000 // Prevent memory bloat

    private init() {
        rooms = persistence.loadRooms()
        unreadCounts = persistence.loadUnreadCounts()
        // Initialize badge on start
        updateGlobalBadge()
    }

    private func updateGlobalBadge() {
        let total = unreadCounts.values.reduce(0, +)
        BadgeManager.shared.updateBadge(count: total)
        
        // Persist
        Task {
            await persistence.saveUnreadCounts(unreadCounts)
        }
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
        } else {
            // Add new message
            activeRoomMessages.append(message)
        }

        // FIX: Sort the array so oldest messages are at the top (index 0)
        // and newest messages are at the bottom.
        activeRoomMessages.sort { $0.timestamp < $1.timestamp }

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
            if let existingIndex = activeRoomMessages.firstIndex(where: { $0.id == message.id }) {
                activeRoomMessages[existingIndex] = message
            } else {
                activeRoomMessages.append(message)
            }
        }
        
        // KEY: Keep the array sorted Oldest (Top) to Newest (Bottom)
        activeRoomMessages.sort { $0.timestamp < $1.timestamp }

        if saveToDisk {
            Task { await persistence.saveMessages(activeRoomMessages, for: roomId) }
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
            updateGlobalBadge()
            // Load cached messages immediately
            let cachedMessages = persistence.loadMessages(for: roomId)
            self.activeRoomMessages = cachedMessages
        } else {
            // Exiting a room
            self.activeRoomMessages = []
        }
    }
    
    // MARK: - Message Management

    /// Fetches messages using smart incremental sync.
    /// If we have cached messages, only fetches messages AFTER the latest cached timestamp.
    /// This dramatically improves room loading times for rooms with history.
    func fetchMessages(for roomId: String) async {
        guard roomId == activeRoomId else { return }

        do {
            // Get the latest cached message timestamp (excluding pending messages)
            let cachedMessages = activeRoomMessages.filter { $0.status != .pending }
            let latestCachedTimestamp = cachedMessages.map { $0.timestamp }.max()

            let newMessages: [ChatMessage]

            if let latestTimestamp = latestCachedTimestamp, !cachedMessages.isEmpty {
                // INCREMENTAL SYNC: Only fetch messages AFTER what we have cached
                print("⚡️ ChatRepository: Incremental sync - fetching messages after \(latestTimestamp)")
                newMessages = try await cloudKit.fetchMessagesAfter(for: roomId, after: latestTimestamp, limit: 100)
                print("⚡️ ChatRepository: Fetched \(newMessages.count) new messages (incremental)")
            } else {
                // FULL FETCH: No cache, fetch recent messages
                print("📥 ChatRepository: Full fetch - no cached messages found")
                newMessages = try await cloudKit.fetchRecentMessages(for: roomId, limit: 50)
            }

            // Skip if no new messages to process
            guard !newMessages.isEmpty || cachedMessages.isEmpty else {
                print("✅ ChatRepository: Messages up to date, no new messages from server")
                return
            }

            // Fetch reactions for new messages only
            var messagesWithReactions = newMessages
            if !newMessages.isEmpty {
                do {
                    let messageIds = newMessages.map { $0.id }
                    let reactionsMap = try await ReactionService.shared.fetchReactions(for: messageIds)

                    // Attach reactions to messages
                    for i in 0..<messagesWithReactions.count {
                        if let reactions = reactionsMap[messagesWithReactions[i].id] {
                            messagesWithReactions[i].reactions = reactions
                        }
                    }
                } catch {
                    print("⚠️ ChatRepository: Could not fetch reactions: \(error)")
                }
            }

            if self.activeRoomId == roomId {
                if latestCachedTimestamp != nil && !cachedMessages.isEmpty {
                    // INCREMENTAL: Merge new messages with existing cache
                    upsertMessages(messagesWithReactions, in: roomId, saveToDisk: true)
                } else {
                    // FULL FETCH: Replace with fetched messages (keep pending)
                    let pendingMessages = self.activeRoomMessages.filter { $0.status == .pending }

                    var newList = messagesWithReactions
                    newList.append(contentsOf: pendingMessages)
                    newList.sort { $0.timestamp < $1.timestamp }

                    withAnimation {
                        self.activeRoomMessages = newList
                    }

                    await persistence.saveMessages(activeRoomMessages, for: roomId)
                }
            }
        } catch {
            print("❌ ChatRepository: Failed to fetch messages: \(error)")
        }
    }

    // Change return type from async to async -> Int
    func fetchOlderMessages(for roomId: String) async -> Int {
        guard roomId == activeRoomId, !activeRoomMessages.isEmpty else { return 0 }

        let oldestMessage = activeRoomMessages.first { $0.status != .pending }
        guard let oldestDate = oldestMessage?.timestamp else { return 0 }

        do {
            let olderMessages = try await cloudKit.fetchRecentMessages(for: roomId, before: oldestDate, limit: 30)
            
            // If empty, return 0 so ViewModel stops the loop
            guard !olderMessages.isEmpty else {
                print("🏁 ChatRepository: No older messages found")
                return 0
            }
            
            // Fetch reactions (existing logic...)
            var messagesWithReactions = olderMessages
            do {
                let messageIds = olderMessages.map { $0.id }
                let reactionsMap = try await ReactionService.shared.fetchReactions(for: messageIds)
                for i in 0..<messagesWithReactions.count {
                    if let reactions = reactionsMap[messagesWithReactions[i].id] {
                        messagesWithReactions[i].reactions = reactions
                    }
                }
            } catch { print("⚠️ Reaction fetch failed") }

            if self.activeRoomId == roomId {
                upsertMessages(messagesWithReactions, in: roomId, saveToDisk: true)
            }
            
            return messagesWithReactions.count // Return the actual count
            
        } catch {
            print("❌ ChatRepository: Failed to fetch older messages: \(error)")
            return 0
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

    /// Called by NotificationRouter when a remote notification arrives.
    /// This is the SINGLE SOURCE OF TRUTH for message deduplication.
    func handleIncomingNotification(_ userInfo: [AnyHashable: Any]) {
        guard let cloudKitNotification = CKNotification(fromRemoteNotificationDictionary: userInfo) as? CKQueryNotification,
              let recordFields = cloudKitNotification.recordFields,
              let roomId = recordFields[ChatMessage.roomIdKey] as? String,
              let recordID = cloudKitNotification.recordID
        else { return }
        
        let messageId = recordID.recordName
        
        // DEDUPLICATION: Check if we've already processed this message
        if processedMessageIds.contains(messageId) {
            print("♻️ ChatRepository: Skipping duplicate message \(messageId)")
            return
        }
        
        // Mark as processed
        processedMessageIds.insert(messageId)
        
        // Cleanup cache if it grows too large
        if processedMessageIds.count > maxProcessedIdsCache {
            print("🧹 ChatRepository: Cleaning processed message cache")
            // Keep only the most recent half
            let toRemove = processedMessageIds.prefix(maxProcessedIdsCache / 2)
            processedMessageIds.subtract(toRemove)
        }

        print("📥 ChatRepository: Processing incoming message for Room \(roomId)")

        // Extract data for room update
        let content = recordFields[ChatMessage.contentKey] as? String ?? "New Message"
        let senderId = recordFields[ChatMessage.senderIdKey] as? String ?? "unknown"
        let timestamp = Date() // Approximate

        // Update unread count for any room (new or existing)
        let currentUserId = UserDefaults.standard.string(forKey: userIdUserDefaultsKey) ?? ""
        if activeRoomId != roomId && senderId != currentUserId {
            unreadCounts[roomId, default: 0] += 1
            updateGlobalBadge()
        }

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
        } else {
            // New room? Fetch all rooms to discover it
            Task { await fetchRooms() }
        }

        // 2. Update Active Room Messages (if valid)
        // CRITICAL FIX: Fetch the full message from CloudKit instead of reconstructing
        if activeRoomId == roomId {
            Task {
                do {
                    // Give CloudKit a breath to move the asset to its temp location
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    
                    let record = try await cloudKit.database.record(for: recordID)
                    let fullMessage = try ChatMessage(from: record)
                    
                    await MainActor.run {
                        withAnimation {
                            upsertMessage(fullMessage, in: roomId)
                        }
                    }
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

    // MARK: - Reaction Notification Handling

    /// Called by NotificationRouter when a reaction notification arrives
    /// This updates the local message's reactions in real-time
    func handleIncomingReaction(_ userInfo: [AnyHashable: Any], queryNotification: CKQueryNotification) {
        guard let recordID = queryNotification.recordID,
              let recordFields = queryNotification.recordFields,
              let messageId = recordFields[MessageReaction.messageIdKey] as? String else {
            print("⚠️ ChatRepository: Invalid reaction notification")
            return
        }

        let notificationType = queryNotification.queryNotificationReason

        print("📥 ChatRepository: Processing reaction notification for message \(messageId), type: \(notificationType.rawValue)")

        // Find the message in active room
        guard let messageIndex = activeRoomMessages.firstIndex(where: { $0.id == messageId }) else {
            print("ℹ️ ChatRepository: Message \(messageId) not in active room, ignoring reaction notification")
            return
        }

        Task {
            do {
                if notificationType == .recordDeleted {
                    // Reaction was removed
                    let reactionId = recordID.recordName
                    print("🗑️ ChatRepository: Removing reaction \(reactionId) from message \(messageId)")

                    await MainActor.run {
                        withAnimation {
                            activeRoomMessages[messageIndex].reactions.removeAll { $0.id == reactionId }
                        }

                        Task {
                            await persistence.saveMessages(activeRoomMessages, for: activeRoomMessages[messageIndex].roomId)
                        }
                    }
                } else {
                    // Reaction was added or updated - fetch the full reaction
                    print("➕ ChatRepository: Fetching new/updated reaction for message \(messageId)")

                    let record = try await cloudKit.database.record(for: recordID)
                    let reaction = try MessageReaction(from: record)

                    await MainActor.run {
                        withAnimation {
                            // Remove old reaction if it exists (for updates)
                            activeRoomMessages[messageIndex].reactions.removeAll { $0.id == reaction.id }
                            // Add new/updated reaction
                            activeRoomMessages[messageIndex].reactions.append(reaction)

                            // Sort reactions by timestamp
                            activeRoomMessages[messageIndex].reactions.sort { $0.timestamp < $1.timestamp }
                        }

                        Task {
                            await persistence.saveMessages(activeRoomMessages, for: activeRoomMessages[messageIndex].roomId)
                        }
                    }

                    print("✅ ChatRepository: Updated reaction on message \(messageId)")
                }
            } catch {
                print("❌ ChatRepository: Failed to process reaction notification: \(error)")
            }
        }
    }
}
