import SwiftUI
import Combine

@MainActor
final class RoomInfoViewModel: ObservableObject {
    @Published var room: ChatRoom
    @Published private(set) var members: [ChatUser] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isUploadingAvatar = false
    @Published private(set) var error: Error?

    private let convexAPI = ConvexChatAPI.shared
    private var cancellables = Set<AnyCancellable>()

    init(room: ChatRoom) {
        self.room = room
    }

    func refreshRoom() async {
        isLoading = true
        error = nil
        do {
            if let updated = try await convexAPI.fetchRoom(roomId: room.id) {
                room = updated
            }
        } catch {
            self.error = error
        }
        isLoading = false
    }

    func loadMembers() async {
        isLoading = true
        error = nil
        do {
            members = try await convexAPI.fetchRoomMembers(roomId: room.id)
        } catch {
            self.error = error
        }
        isLoading = false
    }

    func updateRoomName(_ newName: String) async {
        guard !newName.isEmpty, newName != room.name else { return }
        isLoading = true
        error = nil
        let oldName = room.name
        let userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
        do {
            try await convexAPI.updateRoom(roomId: room.id, userId: userId, name: newName, description: room.description)
            var updated = room
            updated = ChatRoom(
                id: room.id, name: newName, createdBy: room.createdBy,
                createdAt: room.createdAt, lastMessage: room.lastMessage,
                lastMessageDate: room.lastMessageDate, participants: room.participants,
                description: room.description, isPrivate: room.isPrivate,
                type: room.type, messageLifetime: room.messageLifetime,
                avatarStorageId: room.avatarStorageId, avatarURL: room.avatarURL
            )
            room = updated
            await sendSystemMessage("\(currentUserName()) changed the room name from \"\(oldName)\" to \"\(newName)\"")
        } catch {
            self.error = error
        }
        isLoading = false
    }

    func updateRoomDescription(_ newDescription: String) async {
        let trimmed = newDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (room.description ?? "") else { return }
        isLoading = true
        error = nil
        let userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
        do {
            try await convexAPI.updateRoom(roomId: room.id, userId: userId, name: room.name, description: trimmed.isEmpty ? nil : trimmed)
            room = ChatRoom(
                id: room.id, name: room.name, createdBy: room.createdBy,
                createdAt: room.createdAt, lastMessage: room.lastMessage,
                lastMessageDate: room.lastMessageDate, participants: room.participants,
                description: trimmed.isEmpty ? nil : trimmed, isPrivate: room.isPrivate,
                type: room.type, messageLifetime: room.messageLifetime,
                avatarStorageId: room.avatarStorageId, avatarURL: room.avatarURL
            )
            await sendSystemMessage("\(currentUserName()) updated the room description")
        } catch {
            self.error = error
        }
        isLoading = false
    }

    func updateRoomPrivacy(_ isPrivate: Bool) async {
        guard isPrivate != room.isPrivate else { return }
        isLoading = true
        error = nil
        let userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
        do {
            try await convexAPI.updateRoom(roomId: room.id, userId: userId, name: room.name, description: room.description, isPrivate: isPrivate)
            room = ChatRoom(
                id: room.id, name: room.name, createdBy: room.createdBy,
                createdAt: room.createdAt, lastMessage: room.lastMessage,
                lastMessageDate: room.lastMessageDate, participants: room.participants,
                description: room.description, isPrivate: isPrivate,
                type: room.type, messageLifetime: room.messageLifetime,
                avatarStorageId: room.avatarStorageId, avatarURL: room.avatarURL
            )
            await sendSystemMessage("\(currentUserName()) made the room \(isPrivate ? "private" : "public")")
        } catch {
            self.error = error
        }
        isLoading = false
    }

    func updateRoomAvatar(_ image: PlatformImage) async {
        guard let data = image.toData() else { return }
        isUploadingAvatar = true
        error = nil
        do {
            // Delete old room avatar from storage before uploading the new one
            if let oldStorageId = room.avatarStorageId {
                do { try await convexAPI.deleteFile(storageId: oldStorageId) }
                catch { print("⚠️ Could not delete old room avatar \(oldStorageId): \(error)") }
            }
            let storageId = try await convexAPI.uploadFile(data: data, mimeType: "image/jpeg")
            try await convexAPI.updateRoomAvatar(roomId: room.id, storageId: storageId)
            room = ChatRoom(
                id: room.id, name: room.name, createdBy: room.createdBy,
                createdAt: room.createdAt, lastMessage: room.lastMessage,
                lastMessageDate: room.lastMessageDate, participants: room.participants,
                description: room.description, isPrivate: room.isPrivate,
                type: room.type, messageLifetime: room.messageLifetime,
                avatarStorageId: storageId, avatarURL: nil
            )
            await sendSystemMessage("\(currentUserName()) updated the room avatar")
        } catch {
            self.error = error
        }
        isUploadingAvatar = false
    }

    func removeMember(_ userId: String) async {
        isLoading = true
        error = nil
        let removedName = members.first { $0.id == userId }?.displayName ?? "a member"
        do {
            try await convexAPI.leaveRoom(roomId: room.id, userId: userId)
            members.removeAll { $0.id == userId }
            var updatedParticipants = room.participants
            updatedParticipants.removeAll { $0 == userId }
            room = ChatRoom(
                id: room.id, name: room.name, createdBy: room.createdBy,
                createdAt: room.createdAt, lastMessage: room.lastMessage,
                lastMessageDate: room.lastMessageDate, participants: updatedParticipants,
                description: room.description, isPrivate: room.isPrivate,
                type: room.type, messageLifetime: room.messageLifetime,
                avatarStorageId: room.avatarStorageId, avatarURL: room.avatarURL
            )
            await sendSystemMessage("\(currentUserName()) removed \(removedName) from the room")
        } catch {
            self.error = error
        }
        isLoading = false
    }

    // MARK: - Private Helpers

    private func currentUserName() -> String {
        return userDefaults.string(forKey: "userName") ?? "Someone"
    }

    private func sendSystemMessage(_ content: String) async {
        let userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
        _ = try? await convexAPI.sendMessage(
            roomId: room.id,
            userId: userId,
            content: content,
            type: .system,
            senderName: ChatMessage.systemSenderName
        )
    }
}
