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
    @Published var roomListTyping: [String: [String]] = [:]  // roomId → [typer names]

    // MARK: - Dependencies
    private let convexAPI = ConvexChatAPI.shared
    private var activeRoomId: String?

    private init() {}

    // MARK: - Subscription Callbacks (called by ConvexSubscriptionManager)

    /// Called when Convex room list subscription delivers updated rooms.
    func handleRoomsUpdate(_ updatedRooms: [ChatRoom]) {
        if !rooms.isEmpty {
            // Rooms that disappeared were deleted or user was removed — notify open views.
            let removedIds = Set(rooms.map { $0.id }).subtracting(updatedRooms.map { $0.id })
            for roomId in removedIds {
                NotificationCenter.default.post(
                    name: NSNotification.Name("RoomWasDeleted"),
                    object: nil,
                    userInfo: ["roomId": roomId]
                )
            }

            // Increment unread counts for rooms that received a new message
            // while the user is not in that room (Convex subscription-driven).
            let previousById = Dictionary(uniqueKeysWithValues: rooms.map { ($0.id, $0) })
            for updated in updatedRooms {
                guard updated.id != activeRoomId,
                      let previous = previousById[updated.id],
                      let newTime = updated.lastMessageDate,
                      let oldTime = previous.lastMessageDate,
                      newTime > oldTime else { continue }
                unreadCounts[updated.id, default: 0] += 1
            }
        }
        withAnimation { rooms = updatedRooms }
        reconcileUnreadCounts()
        updateGlobalBadge()
    }

    /// Called when the typing-for-user subscription delivers updated data.
    func handleRoomListTypingUpdate(_ typingMap: [String: [String]]) {
        roomListTyping = typingMap
    }

    /// Called when Convex messages subscription delivers updated message list.
    /// The list is COMPLETE — Convex is authoritative.
    func handleMessagesSubscriptionUpdate(_ serverMessages: [ChatMessage], for roomId: String) {
        guard roomId == activeRoomId else { return }

        let serverIds = Set(serverMessages.map { $0.id })
        // For text messages: match by senderId+content
        let serverTextKeys = Set(
            serverMessages.filter { $0.mediaStorageId == nil }
                .map { "\($0.senderId)|\($0.content)" }
        )
        // For media messages: match by storageId (more accurate — avoids "📷 Photo" key collisions)
        let serverStorageIds = Set(serverMessages.compactMap { $0.mediaStorageId })

        // Preserve local assetURLs from confirmed pending messages so sender
        // keeps seeing their image after the server message replaces the optimistic.
        var storageIdToAssetURL: [String: URL] = [:]

        let unconfirmed = activeRoomMessages.filter { pending in
            guard pending.status == .pending || pending.status == .error else { return false }
            guard !serverIds.contains(pending.id) else { return false }
            if pending.status == .pending {
                if let storageId = pending.mediaStorageId {
                    // Media: confirmed when server has same storageId
                    if serverStorageIds.contains(storageId) {
                        if let assetURL = pending.assetURL { storageIdToAssetURL[storageId] = assetURL }
                        return false
                    }
                } else if serverTextKeys.contains("\(pending.senderId)|\(pending.content)") {
                    // Text: confirmed when server has same sender+content
                    return false
                }
            }
            return true
        }

        // Apply preserved assetURLs to the matching server messages
        var merged: [ChatMessage] = serverMessages.map { msg in
            guard let storageId = msg.mediaStorageId,
                  let assetURL = storageIdToAssetURL[storageId],
                  msg.assetURL == nil else { return msg }
            var m = msg
            m.assetURL = assetURL
            return m
        }
        merged.append(contentsOf: unconfirmed)
        merged.sort { $0.timestamp < $1.timestamp }

        activeRoomMessages = merged
    }

    // MARK: - Optimistic Helpers for Media Sending

    /// Insert a pending message immediately (before upload completes) so the UI shows feedback.
    func insertOptimistic(_ message: ChatMessage) {
        var pending = message
        pending.status = .pending
        upsertMessage(pending, in: message.roomId)
    }

    /// Mark an optimistic message as failed (e.g. upload error).
    func failOptimistic(id: String, in roomId: String) {
        guard roomId == activeRoomId,
              let idx = activeRoomMessages.firstIndex(where: { $0.id == id }) else { return }
        activeRoomMessages[idx].status = .error
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
            AppLogger.shared.logError("ChatRepository.fetchRooms", error)
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

    /// Clears the active room only if it still matches the expected roomId.
    /// Safe to call from deinit Tasks where a new room may already be active.
    func clearIfActive(_ roomId: String) {
        guard activeRoomId == roomId else { return }
        setActiveRoom(nil)
    }

    func setActiveRoom(_ roomId: String?) {
        activeRoomId = roomId
        if let roomId {
            ConvexSubscriptionManager.shared.subscribeToRoom(roomId)
            // Defer @Published mutations — setActiveRoom is called from ChatRoomViewModel.init
            // which runs during @StateObject creation (a view update). Publishing synchronously
            // here would trigger "Publishing from within view updates" warnings.
            Task { [weak self] in
                self?.markRoomAsRead(roomId: roomId)
                self?.activeRoomMessages = []
            }
        } else {
            ConvexSubscriptionManager.shared.unsubscribeFromCurrentRoom()
            Task { [weak self] in
                self?.activeRoomMessages = []
            }
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
            AppLogger.shared.logError("ChatRepository.fetchMessages", error)
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
            AppLogger.shared.logError("ChatRepository.fetchOlderMessages", error)
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
            AppLogger.shared.logError("ChatRepository.sendMessage", error)
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
            AppLogger.shared.logError("ChatRepository.deleteMessage", error)
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
