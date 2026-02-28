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
        
        // Ensure unread counts only exist for rooms we actually have
        reconcileUnreadCounts()
        
        // Initialize badge on start
        updateGlobalBadge()

        Task {
            await persistence.runStorageMaintenance(validRoomIds: Set(rooms.map { $0.id }))
        }
    }

    /// Ensures unreadCounts dictionary only contains entries for rooms currently in the 'rooms' list.
    /// This prevents "ghost" badge counts from deleted or left rooms.
    private func reconcileUnreadCounts() {
        let validRoomIds = Set(rooms.map { $0.id })
        let staleRoomIds = unreadCounts.keys.filter { !validRoomIds.contains($0) }
        
        if !staleRoomIds.isEmpty {
            print("🧹 ChatRepository: Removing \(staleRoomIds.count) stale unread count entries")
            for roomId in staleRoomIds {
                unreadCounts.removeValue(forKey: roomId)
            }
        }
    }

    private func updateGlobalBadge() {
        // Sum only for rooms that are in our local list
        let validRoomIds = Set(rooms.map { $0.id })
        let total = unreadCounts.filter { validRoomIds.contains($0.key) }.values.reduce(0, +)
        
        BadgeManager.shared.updateBadge(count: total)
        
        // Persist
        Task {
            await persistence.saveUnreadCounts(unreadCounts)
        }
    }

    private func saveRoomsAndRunMaintenance() async {
        await persistence.saveRooms(rooms)
        await persistence.runStorageMaintenance(validRoomIds: Set(rooms.map { $0.id }))
    }

    private func deleteLocalRoomCache(roomId: String) async {
        await persistence.deleteMessageCache(for: roomId)
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

        if let existingIndex = activeRoomMessages.firstIndex(where: { $0.id == message.id }) {
            // Preserve locally-synced reactions when the incoming message has none
            // (ChatMessage(from: CKRecord) always sets reactions = []).
            // Reaction adds/deletes are handled independently by handleIncomingReaction.
            // Full reaction sync happens in fetchMessages/fetchOlderMessages.
            var updated = message
            if updated.reactions.isEmpty {
                updated.reactions = activeRoomMessages[existingIndex].reactions
            }
            activeRoomMessages[existingIndex] = updated
        } else {
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
                var updated = message
                if updated.reactions.isEmpty {
                    updated.reactions = activeRoomMessages[existingIndex].reactions
                }
                activeRoomMessages[existingIndex] = updated
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

    /// Refresh reactions for a slice of messages without requiring new message records.
    /// This keeps reaction state in sync across devices even when only reactions changed.
    private func refreshReactionsForCachedMessages(in roomId: String) async {
        guard roomId == activeRoomId, !activeRoomMessages.isEmpty else { return }

        let messageIdsToRefresh = Array(activeRoomMessages.suffix(120).map { $0.id })
        let messageIdSet = Set(messageIdsToRefresh)
        guard !messageIdSet.isEmpty else { return }

        do {
            let reactionsMap = try await ReactionService.shared.fetchReactions(for: messageIdsToRefresh)
            var didChange = false

            for index in activeRoomMessages.indices {
                let messageId = activeRoomMessages[index].id
                guard messageIdSet.contains(messageId) else { continue }

                let refreshed = (reactionsMap[messageId] ?? []).sorted { $0.timestamp < $1.timestamp }
                if activeRoomMessages[index].reactions != refreshed {
                    activeRoomMessages[index].reactions = refreshed
                    didChange = true
                }
            }

            if didChange {
                await persistence.saveMessages(activeRoomMessages, for: roomId)
                print("🔄 ChatRepository: Refreshed cached reactions for room \(roomId)")
            }
        } catch {
            print("⚠️ ChatRepository: Could not refresh cached reactions: \(error)")
        }
    }


    // MARK: - Room Management
    func fetchRooms() async {
        do {
            let fetchedRooms = try await cloudKit.fetchChatRooms()
            self.rooms = fetchedRooms
            
            // Reconcile unread counts with the updated room list
            reconcileUnreadCounts()
            updateGlobalBadge()
            
            Task {
                await saveRoomsAndRunMaintenance()
            }
            print("✅ ChatRepository: Fetched \(fetchedRooms.count) rooms")
        } catch {
            print("❌ ChatRepository: Failed to fetch rooms: \(error)")
        }
    }

    /// Optimistically adds a room to the local list immediately (before CloudKit sync completes)
    /// This ensures the UI updates instantly after room creation
    func addRoomOptimistically(_ room: ChatRoom) {
        // Only add if not already present
        if !rooms.contains(where: { $0.id == room.id }) {
            withAnimation {
                rooms.insert(room, at: 0)  // Add to top of list (newest first)
            }
            Task {
                await saveRoomsAndRunMaintenance()
            }
            print("✅ ChatRepository: Optimistically added room '\(room.name)'")
        }
    }

    /// Removes a room from the local list immediately (for optimistic UI updates)
    func removeRoomOptimistically(_ roomId: String) {
        withAnimation {
            rooms.removeAll { $0.id == roomId }
        }
        Task {
            await saveRoomsAndRunMaintenance()
            await deleteLocalRoomCache(roomId: roomId)
        }
        print("✅ ChatRepository: Optimistically removed room \(roomId)")
    }

    func markRoomAsRead(roomId: String) {
        unreadCounts[roomId] = 0
        updateGlobalBadge()
    }
    
    func setActiveRoom(_ roomId: String?) {
        self.activeRoomId = roomId
        if let roomId = roomId {
            // Clear unread count
            markRoomAsRead(roomId: roomId)
            // Load cached messages immediately
            let cachedMessages = persistence.loadMessages(for: roomId)
            self.activeRoomMessages = cachedMessages
        } else {
            // Exiting a room
            self.activeRoomMessages = []
        }
    }
    
    // MARK: - Message Management

    /// Track fetch count for periodic full sync
    private var incrementalFetchCount: [String: Int] = [:]
    private let fullSyncInterval = 5 // Do full sync every N incremental fetches

    /// Fetches messages using smart incremental sync with overlap.
    /// Uses overlap to catch any messages that might have been missed.
    /// Periodically does a full sync to ensure no gaps.
    func fetchMessages(for roomId: String, forceFullSync: Bool = false) async {
        guard roomId == activeRoomId else { return }

        do {
            // Get the latest cached message timestamp (excluding pending messages)
            let cachedMessages = activeRoomMessages.filter { $0.status != .pending }
            let latestCachedTimestamp = cachedMessages.map { $0.timestamp }.max()

            // Track incremental fetches for periodic full sync
            let fetchCount = incrementalFetchCount[roomId] ?? 0
            let shouldDoFullSync = forceFullSync || (fetchCount > 0 && fetchCount % fullSyncInterval == 0)

            let newMessages: [ChatMessage]

            if shouldDoFullSync {
                // PERIODIC FULL SYNC: Fetch all recent messages to catch any gaps
                print("🔄 ChatRepository: Periodic full sync for room \(roomId)")
                newMessages = try await cloudKit.fetchRecentMessages(for: roomId, limit: 100)
                print("🔄 ChatRepository: Full sync fetched \(newMessages.count) messages")
            } else if let latestTimestamp = latestCachedTimestamp, !cachedMessages.isEmpty {
                // INCREMENTAL SYNC WITH OVERLAP: Fetch messages with 2-minute overlap
                // This ensures we catch any messages that might have been missed due to
                // network issues, race conditions, or clock skew
                let overlapSeconds: TimeInterval = 120 // 2 minutes overlap
                let fetchFromTimestamp = latestTimestamp.addingTimeInterval(-overlapSeconds)

                print("⚡️ ChatRepository: Incremental sync with overlap - fetching messages after \(fetchFromTimestamp)")
                newMessages = try await cloudKit.fetchMessagesAfter(for: roomId, after: fetchFromTimestamp, limit: 100)
                print("⚡️ ChatRepository: Fetched \(newMessages.count) messages (incremental with overlap)")
            } else {
                // FULL FETCH: No cache, fetch recent messages
                print("📥 ChatRepository: Full fetch - no cached messages found")
                newMessages = try await cloudKit.fetchRecentMessages(for: roomId, limit: 50)
            }

            // Update fetch count
            incrementalFetchCount[roomId] = fetchCount + 1

            // If there are no new messages, still refresh reactions for cached messages.
            if newMessages.isEmpty && !cachedMessages.isEmpty {
                await refreshReactionsForCachedMessages(in: roomId)
                print("✅ ChatRepository: Messages up to date, refreshed reactions only")
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
                // Always use upsert to merge and deduplicate
                upsertMessages(messagesWithReactions, in: roomId, saveToDisk: true)
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
        let messageType = recordFields[ChatMessage.typeKey] as? String

        // Check for member change system messages - update room data
        if messageType == MessageType.system.rawValue {
            let isRemoval = content.contains("removed") && content.contains("from the room")
            let isLeave = content.contains("left the room")
            let isJoin = content.contains("joined the room")
            let isRoomDeleted = content.contains("deleted this room")

            if isRoomDeleted {
                // Room is being deleted - remove from list immediately
                Task {
                    await handleRoomDeletedNotification(roomId: roomId)
                }
            } else if isRemoval || isLeave || isJoin {
                Task {
                    // Always refresh room to update participant count in list
                    await refreshRoomInList(roomId: roomId)
                    // Also check if current user was removed (if we're in this room)
                    if isRemoval && activeRoomId == roomId {
                        await checkMembershipAfterRemoval(roomId: roomId)
                    }
                }
            }
        }

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
                await saveRoomsAndRunMaintenance()
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
                await saveRoomsAndRunMaintenance()
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

    // MARK: - Room List Updates (triggered by system messages)

    /// Handles room deletion notification - removes room from list immediately
    private func handleRoomDeletedNotification(roomId: String) async {
        print("🗑️ ChatRepository: Room \(roomId) is being deleted, removing from list")

        await MainActor.run {
            withAnimation {
                rooms.removeAll { $0.id == roomId }
                // Clean up unread count for the deleted room
                unreadCounts.removeValue(forKey: roomId)
                updateGlobalBadge()
            }

            // Always post notification - ContentView, ChatRoomView, and RoomInfoView all listen
            NotificationCenter.default.post(
                name: NSNotification.Name("RoomWasDeleted"),
                object: nil,
                userInfo: ["roomId": roomId]
            )
        }

        // Persist and unsubscribe
        await saveRoomsAndRunMaintenance()
        await deleteLocalRoomCache(roomId: roomId)
        await NotificationSubscriptionManager.shared.unsubscribeFromRoom(roomId)
    }

    /// Refreshes a room's data in the local list (e.g., after participant changes)
    /// This updates participant count and other room details in the lobby
    private func refreshRoomInList(roomId: String) async {
        do {
            if let latestRoom = try await cloudKit.fetchChatRoom(byId: roomId) {
                // Update the room in our local list
                await MainActor.run {
                    if let index = rooms.firstIndex(where: { $0.id == roomId }) {
                        withAnimation {
                            rooms[index] = latestRoom
                        }
                        print("✅ ChatRepository: Updated room \(roomId) in list (participants: \(latestRoom.participants.count))")
                    }
                }
                // Persist
                await saveRoomsAndRunMaintenance()
            } else {
                // Room no longer exists - remove from list
                print("⚠️ ChatRepository: Room \(roomId) no longer exists, removing from list")
                await MainActor.run {
                    withAnimation {
                        rooms.removeAll { $0.id == roomId }
                    }
                    NotificationCenter.default.post(
                        name: NSNotification.Name("RoomWasDeleted"),
                        object: nil,
                        userInfo: ["roomId": roomId]
                    )
                }
                await saveRoomsAndRunMaintenance()
                await deleteLocalRoomCache(roomId: roomId)
            }
        } catch {
            print("⚠️ ChatRepository: Failed to refresh room \(roomId): \(error)")
        }
    }

    // MARK: - Membership Check (triggered by removal system messages)

    /// Checks if current user is still a member after a removal system message
    /// This is only called when we receive a "removed X from the room" message
    private func checkMembershipAfterRemoval(roomId: String) async {
        let currentUserId = UserDefaults.standard.string(forKey: userIdUserDefaultsKey) ?? ""

        do {
            if let room = try await cloudKit.fetchChatRoom(byId: roomId) {
                if !room.participants.contains(currentUserId) {
                    // Current user was removed
                    print("⚠️ ChatRepository: Current user was removed from room \(roomId)")
                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("UserRemovedFromRoom"),
                            object: nil,
                            userInfo: ["roomId": roomId]
                        )
                    }
                }
            }
        } catch {
            print("⚠️ ChatRepository: Failed to check membership after removal: \(error)")
        }
    }

    // MARK: - Room Change Notification Handling

    /// Called by NotificationRouter when a room change notification arrives
    /// This handles membership changes and room deletions in real-time
    func handleRoomChange(_ userInfo: [AnyHashable: Any], queryNotification: CKQueryNotification, roomId: String) {
        let notificationType = queryNotification.queryNotificationReason

        print("📥 ChatRepository: Processing room change notification for room \(roomId), type: \(notificationType.rawValue)")

        let currentUserId = UserDefaults.standard.string(forKey: userIdUserDefaultsKey) ?? ""

        if notificationType == .recordDeleted {
            // Room was deleted
            print("🗑️ ChatRepository: Room \(roomId) was deleted")
            handleRoomDeleted(roomId: roomId)
        } else if notificationType == .recordUpdated {
            // Room was updated - check if we're still a participant
            Task {
                await handleRoomUpdated(roomId: roomId, currentUserId: currentUserId)
            }
        }
    }

    /// Handle room deletion - remove from local state and notify UI
    private func handleRoomDeleted(roomId: String) {
        // Remove from local rooms list
        withAnimation {
            rooms.removeAll { $0.id == roomId }
            // Clean up unread count for the deleted room
            unreadCounts.removeValue(forKey: roomId)
            updateGlobalBadge()
        }

        // Persist
        Task {
            await saveRoomsAndRunMaintenance()
            await deleteLocalRoomCache(roomId: roomId)
        }

        // If user is currently in this room, notify them
        if activeRoomId == roomId {
            print("⚠️ ChatRepository: User is in deleted room, posting notification")
            NotificationCenter.default.post(
                name: NSNotification.Name("RoomWasDeleted"),
                object: nil,
                userInfo: ["roomId": roomId]
            )
        }

        // Unsubscribe from this room
        Task {
            await NotificationSubscriptionManager.shared.unsubscribeFromRoom(roomId)
        }

        print("✅ ChatRepository: Handled room deletion for \(roomId)")
    }

    /// Handle room update - check membership and update local state
    private func handleRoomUpdated(roomId: String, currentUserId: String) async {
        do {
            // Fetch the latest room data from CloudKit
            if let latestRoom = try await cloudKit.fetchChatRoom(byId: roomId) {
                let isStillMember = latestRoom.participants.contains(currentUserId)

                if !isStillMember {
                    // User was removed from the room
                    print("⚠️ ChatRepository: User was removed from room \(roomId)")

                    // Remove from local rooms list
                    await MainActor.run {
                        withAnimation {
                            rooms.removeAll { $0.id == roomId }
                            // Clean up unread count when user is removed
                            unreadCounts.removeValue(forKey: roomId)
                            updateGlobalBadge()
                        }
                    }

                    // Persist
                    await saveRoomsAndRunMaintenance()
                    await deleteLocalRoomCache(roomId: roomId)

                    // If user is currently in this room, notify them
                    if activeRoomId == roomId {
                        await MainActor.run {
                            NotificationCenter.default.post(
                                name: NSNotification.Name("UserRemovedFromRoom"),
                                object: nil,
                                userInfo: ["roomId": roomId]
                            )
                        }
                    }

                    // Unsubscribe from this room
                    await NotificationSubscriptionManager.shared.unsubscribeFromRoom(roomId)

                    print("✅ ChatRepository: Handled user removal from room \(roomId)")
                } else {
                    // User is still a member - update room details locally
                    await MainActor.run {
                        if let index = rooms.firstIndex(where: { $0.id == roomId }) {
                            withAnimation {
                                rooms[index] = latestRoom
                            }
                        }
                    }

                    // Persist
                    await saveRoomsAndRunMaintenance()

                    print("✅ ChatRepository: Updated room details for \(roomId)")
                }
            } else {
                // Room doesn't exist anymore (deleted)
                handleRoomDeleted(roomId: roomId)
            }
        } catch {
            print("❌ ChatRepository: Failed to fetch room update: \(error)")
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

        // Check if the message exists in active room before starting async work
        guard activeRoomMessages.contains(where: { $0.id == messageId }) else {
            print("ℹ️ ChatRepository: Message \(messageId) not in active room, ignoring reaction notification")
            return
        }

        Task {
            do {
                if notificationType == .recordDeleted {
                    // Reaction was removed
                    let reactionId = recordID.recordName
                    print("🗑️ ChatRepository: Removing reaction \(reactionId) from message \(messageId)")

                    // Re-find index after async boundary to avoid stale index
                    guard let idx = activeRoomMessages.firstIndex(where: { $0.id == messageId }) else { return }
                    withAnimation {
                        activeRoomMessages[idx].reactions.removeAll { $0.id == reactionId }
                    }
                    Task {
                        await persistence.saveMessages(activeRoomMessages, for: activeRoomMessages[idx].roomId)
                    }
                } else {
                    // Reaction was added or updated - fetch the full reaction
                    print("➕ ChatRepository: Fetching new/updated reaction for message \(messageId)")

                    let record = try await cloudKit.database.record(for: recordID)
                    let reaction = try MessageReaction(from: record)

                    // Re-find index after async boundary to avoid stale index
                    guard let idx = activeRoomMessages.firstIndex(where: { $0.id == messageId }) else { return }
                    withAnimation {
                        // Remove old reaction if it exists (for updates)
                        activeRoomMessages[idx].reactions.removeAll { $0.id == reaction.id }
                        // Add new/updated reaction
                        activeRoomMessages[idx].reactions.append(reaction)
                        // Sort reactions by timestamp
                        activeRoomMessages[idx].reactions.sort { $0.timestamp < $1.timestamp }
                    }
                    Task {
                        await persistence.saveMessages(activeRoomMessages, for: activeRoomMessages[idx].roomId)
                    }

                    print("✅ ChatRepository: Updated reaction on message \(messageId)")
                }
            } catch {
                print("❌ ChatRepository: Failed to process reaction notification: \(error)")
            }
        }
    }
}
