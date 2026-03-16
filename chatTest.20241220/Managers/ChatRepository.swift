import Combine
import Foundation
import SwiftUI

/// Single Source of Truth for all chat data.
/// Real-time updates arrive via ConvexSubscriptionManager.
/// No local disk cache — Convex is the authoritative source.
@MainActor
class ChatRepository: ObservableObject {
    static let shared = ChatRepository()

    // MARK: - Published State
    @Published var rooms: [ChatRoom] = []
    @Published var activeRoomMessages: [ChatMessage] = []
    @Published var unreadCounts: [String: Int] = [:]

    // MARK: - Dependencies
    private let convexAPI = ConvexChatAPI.shared
    private var activeRoomId: String?

    private init() {}

    // MARK: - Subscription Callbacks (called by ConvexSubscriptionManager)

    /// Called when Convex room list subscription delivers updated rooms.
    func handleRoomsUpdate(_ updatedRooms: [ChatRoom]) {
        withAnimation { rooms = updatedRooms }
        reconcileUnreadCounts()
        updateGlobalBadge()
    }

    /// Called when Convex messages subscription delivers updated message list.
    /// The list is COMPLETE — Convex is authoritative.
    func handleMessagesSubscriptionUpdate(_ serverMessages: [ChatMessage], for roomId: String) {
        guard roomId == activeRoomId else { return }

        let serverIds = Set(serverMessages.map { $0.id })
        // Match pending messages by senderId+content — when the server delivers it, drop the optimistic
        let serverContentKeys = Set(serverMessages.map { "\($0.senderId)|\($0.content)" })

        let unconfirmed = activeRoomMessages.filter {
            guard $0.status == .pending || $0.status == .error else { return false }
            guard !serverIds.contains($0.id) else { return false }
            // If server already has this content from same sender, optimistic is confirmed — drop it
            if $0.status == .pending && serverContentKeys.contains("\($0.senderId)|\($0.content)") {
                return false
            }
            return true
        }

        var merged = serverMessages
        merged.append(contentsOf: unconfirmed)
        merged.sort { $0.timestamp < $1.timestamp }

        activeRoomMessages = merged
    }

    // MARK: - Unread / Badge Helpers

    private func reconcileUnreadCounts() {
        let validIds = Set(rooms.map { $0.id })
        for id in unreadCounts.keys where !validIds.contains(id) {
            unreadCounts.removeValue(forKey: id)
        }
    }

    private func updateGlobalBadge() {
        let validIds = Set(rooms.map { $0.id })
        let total = unreadCounts.filter { validIds.contains($0.key) }.values.reduce(0, +)
        BadgeManager.shared.updateBadge(count: total)
    }

    // MARK: - Room Management

    func fetchRooms() async {
        guard let userId = userDefaults.string(forKey: userIdUserDefaultsKey) else { return }
        do {
            let fetched = try await convexAPI.fetchUserRooms(userId: userId)
            withAnimation { rooms = fetched }
            reconcileUnreadCounts()
            updateGlobalBadge()
        } catch {
            print("❌ ChatRepository: Failed to fetch rooms: \(error)")
        }
    }

    func addRoomOptimistically(_ room: ChatRoom) {
        guard !rooms.contains(where: { $0.id == room.id }) else { return }
        withAnimation { rooms.insert(room, at: 0) }
    }

    func removeRoomOptimistically(_ roomId: String) {
        withAnimation { rooms.removeAll { $0.id == roomId } }
    }

    func markRoomAsRead(roomId: String) {
        unreadCounts[roomId] = 0
        updateGlobalBadge()
    }

    func setActiveRoom(_ roomId: String?) {
        activeRoomId = roomId
        if let roomId {
            markRoomAsRead(roomId: roomId)
            activeRoomMessages = []
            ConvexSubscriptionManager.shared.subscribeToRoom(roomId)
        } else {
            ConvexSubscriptionManager.shared.unsubscribeFromCurrentRoom()
            activeRoomMessages = []
        }
    }

    // MARK: - Message Management

    func fetchMessages(for roomId: String, forceFullSync: Bool = false) async {
        guard roomId == activeRoomId else { return }
        do {
            let messages: [ChatMessage]
            let cached = activeRoomMessages.filter { $0.status != .pending }
            let latestTimestamp = cached.map { $0.timestamp }.max()

            if forceFullSync || latestTimestamp == nil {
                messages = try await convexAPI.fetchMessages(roomId: roomId, limit: 100)
            } else {
                let since = latestTimestamp!.addingTimeInterval(-120)
                messages = try await convexAPI.fetchMessagesSince(roomId: roomId, since: since)
            }

            if !messages.isEmpty {
                upsertMessages(messages, in: roomId)
            }
        } catch {
            print("❌ ChatRepository: Failed to fetch messages: \(error)")
        }
    }

    func fetchOlderMessages(for roomId: String) async -> Int {
        guard roomId == activeRoomId, !activeRoomMessages.isEmpty else { return 0 }
        let oldest = activeRoomMessages.first { $0.status != .pending }
        guard let oldestDate = oldest?.timestamp else { return 0 }
        do {
            let older = try await convexAPI.fetchMessagesBefore(roomId: roomId, before: oldestDate, limit: 30)
            guard !older.isEmpty else { return 0 }
            upsertMessages(older, in: roomId)
            return older.count
        } catch {
            print("❌ ChatRepository: Failed to fetch older messages: \(error)")
            return 0
        }
    }

    func sendMessage(_ message: ChatMessage) async {
        guard let userId = userDefaults.string(forKey: userIdUserDefaultsKey) else { return }

        // Optimistic update
        var pending = message
        pending.status = .pending
        upsertMessage(pending, in: message.roomId)

        do {
            _ = try await convexAPI.sendMessage(
                roomId: message.roomId,
                userId: userId,
                content: message.content,
                type: message.type,
                senderName: message.senderName,
                mediaStorageId: message.mediaStorageId
            )
            // Don't remove optimistic here — handleMessagesSubscriptionUpdate will
            // drop it atomically when the server confirms the same content.
            updateLocalRoom(for: message)
        } catch {
            print("❌ ChatRepository: Failed to send message: \(error)")
            var errorMessage = message
            errorMessage.status = .error
            upsertMessage(errorMessage, in: message.roomId)
        }
    }

    func deleteMessage(_ messageId: String, in roomId: String) async {
        guard let userId = userDefaults.string(forKey: userIdUserDefaultsKey) else { return }

        if roomId == activeRoomId {
            withAnimation { activeRoomMessages.removeAll { $0.id == messageId } }
        }
        do {
            try await convexAPI.deleteMessage(messageId: messageId, userId: userId)
        } catch {
            print("❌ ChatRepository: Failed to delete message: \(error)")
            if roomId == activeRoomId { await fetchMessages(for: roomId) }
        }
    }

    // MARK: - Push Notification Handling (background wake only)

    func handleIncomingPush(_ userInfo: [AnyHashable: Any]) {
        guard let roomId = userInfo["roomId"] as? String else { return }
        let senderId = userInfo["senderId"] as? String ?? ""
        let currentUserId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""

        if activeRoomId != roomId && senderId != currentUserId {
            unreadCounts[roomId, default: 0] += 1
            updateGlobalBadge()
        }

        if let content = userInfo["content"] as? String,
           let index = rooms.firstIndex(where: { $0.id == roomId }) {
            var updated = rooms[index]
            updated.lastMessage = content
            updated.lastMessageDate = Date()
            withAnimation {
                rooms[index] = updated
                let r = rooms.remove(at: index)
                rooms.insert(r, at: 0)
            }
        } else if !rooms.contains(where: { $0.id == roomId }) {
            Task { await fetchRooms() }
        }
    }

    // MARK: - Room Deleted / Removed Notification

    func handleRoomDeleted(roomId: String) {
        withAnimation {
            rooms.removeAll { $0.id == roomId }
            unreadCounts.removeValue(forKey: roomId)
            updateGlobalBadge()
        }
        NotificationCenter.default.post(
            name: NSNotification.Name("RoomWasDeleted"),
            object: nil,
            userInfo: ["roomId": roomId]
        )
    }

    // MARK: - Private Helpers

    private func upsertMessage(_ message: ChatMessage, in roomId: String) {
        guard roomId == activeRoomId else { return }
        if let idx = activeRoomMessages.firstIndex(where: { $0.id == message.id }) {
            var updated = message
            if updated.reactions.isEmpty { updated.reactions = activeRoomMessages[idx].reactions }
            activeRoomMessages[idx] = updated
        } else {
            activeRoomMessages.append(message)
        }
        activeRoomMessages.sort { $0.timestamp < $1.timestamp }
    }

    private func upsertMessages(_ messages: [ChatMessage], in roomId: String) {
        guard roomId == activeRoomId else { return }
        for message in messages {
            if let idx = activeRoomMessages.firstIndex(where: { $0.id == message.id }) {
                var updated = message
                if updated.reactions.isEmpty { updated.reactions = activeRoomMessages[idx].reactions }
                activeRoomMessages[idx] = updated
            } else {
                activeRoomMessages.append(message)
            }
        }
        activeRoomMessages.sort { $0.timestamp < $1.timestamp }
    }

    private func updateLocalRoom(for message: ChatMessage) {
        guard let idx = rooms.firstIndex(where: { $0.id == message.roomId }) else { return }
        var updated = rooms[idx]
        updated.lastMessage = message.content
        updated.lastMessageDate = message.timestamp
        withAnimation {
            rooms[idx] = updated
            let r = rooms.remove(at: idx)
            rooms.insert(r, at: 0)
        }
    }
}
