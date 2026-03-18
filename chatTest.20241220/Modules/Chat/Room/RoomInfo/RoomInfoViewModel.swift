import SwiftUI
import Combine
import ConvexMobile

@MainActor
final class RoomInfoViewModel: ObservableObject {
    @Published var room: ChatRoom
    @Published private(set) var members: [ChatUser] = []
    @Published private(set) var isLoading = true
    @Published private(set) var isUploadingAvatar = false

    private let convexAPI = ConvexChatAPI.shared
    private let client = ConvexService.shared.client
    private var roomSubscription: AnyCancellable?
    private var membersSubscription: AnyCancellable?

    init(room: ChatRoom) {
        self.room = room
    }

    // MARK: - Subscriptions

    func startSubscriptions() {
        let roomId = room.id

        roomSubscription = client
            .subscribe(to: "rooms:getRoom", with: ["roomId": roomId], yielding: ConvexRoomDoc?.self)
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] doc in
                    guard let self, let doc else { return }
                    self.room = doc.toChatRoom()
                    self.isLoading = false
                }
            )

        membersSubscription = client
            .subscribe(to: "rooms:getMembers", with: ["roomId": roomId], yielding: [ConvexUserDoc].self)
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] docs in
                    self?.members = docs.map { $0.toChatUser() }
                    self?.isLoading = false
                }
            )
    }

    func stopSubscriptions() {
        roomSubscription?.cancel()
        roomSubscription = nil
        membersSubscription?.cancel()
        membersSubscription = nil
    }

    // MARK: - Room Updates

    func updateRoomName(_ newName: String) async {
        guard !newName.isEmpty, newName != room.name else { return }
        isLoading = true
        let oldName = room.name
        let userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
        do {
            try await convexAPI.updateRoom(roomId: room.id, userId: userId, name: newName, description: room.description)
            await sendSystemMessage("\(currentUserName()) changed the room name from \"\(oldName)\" to \"\(newName)\"")
        } catch {
            AlertManager.shared.showAlert(title: "Error", message: friendlyErrorMessage(error))
        }
        isLoading = false
    }

    func updateRoomDescription(_ newDescription: String) async {
        let trimmed = newDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (room.description ?? "") else { return }
        isLoading = true
        let userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
        do {
            try await convexAPI.updateRoom(roomId: room.id, userId: userId, name: room.name, description: trimmed.isEmpty ? nil : trimmed)
            await sendSystemMessage("\(currentUserName()) updated the room description")
        } catch {
            AlertManager.shared.showAlert(title: "Error", message: friendlyErrorMessage(error))
        }
        isLoading = false
    }

    func updateRoomPrivacy(_ isPrivate: Bool) async {
        guard isPrivate != room.isPrivate else { return }
        isLoading = true
        let userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
        do {
            try await convexAPI.updateRoom(roomId: room.id, userId: userId, name: room.name, description: room.description, isPrivate: isPrivate)
            await sendSystemMessage("\(currentUserName()) made the room \(isPrivate ? "private" : "public")")
        } catch {
            AlertManager.shared.showAlert(title: "Error", message: friendlyErrorMessage(error))
        }
        isLoading = false
    }

    func updateRoomAvatar(_ image: PlatformImage) async {
        guard let data = image.toData() else { return }
        isUploadingAvatar = true
        do {
            if let oldStorageId = room.avatarStorageId {
                do { try await convexAPI.deleteFile(storageId: oldStorageId) }
                catch { print("⚠️ Could not delete old room avatar \(oldStorageId): \(error)") }
            }
            let storageId = try await convexAPI.uploadFile(data: data, mimeType: "image/jpeg")
            if let cachedURL = saveTempImage(data: data) {
                ConvexFileCacheService.shared.replaceCachedFile(storageId: storageId, with: cachedURL)
            }
            let userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
            try await convexAPI.updateRoomAvatar(roomId: room.id, userId: userId, storageId: storageId)
            await sendSystemMessage("\(currentUserName()) updated the room avatar")
        } catch {
            AlertManager.shared.showAlert(title: "Error", message: friendlyErrorMessage(error))
        }
        isUploadingAvatar = false
    }

    private func saveTempImage(data: Data) -> URL? {
        let fileManager = FileManager.default
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let assetsDirectory = documentsDirectory.appendingPathComponent("ChatAssets", isDirectory: true)
        if !fileManager.fileExists(atPath: assetsDirectory.path) {
            try? fileManager.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
        }

        let fileURL = assetsDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        do {
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            return nil
        }
    }

    func updateMessageLifetime(_ seconds: TimeInterval) async {
        isLoading = true
        let userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
        do {
            try await convexAPI.updateRoom(
                roomId: room.id,
                userId: userId,
                name: room.name,
                description: room.description,
                messageLifetime: seconds
            )
            await sendSystemMessage("\(currentUserName()) changed message lifetime to \(formatLifetime(seconds))")
        } catch {
            AlertManager.shared.showAlert(title: "Error", message: friendlyErrorMessage(error))
        }
        isLoading = false
    }

    func removeMember(_ userId: String) async {
        isLoading = true
        let removedName = members.first { $0.id == userId }?.displayName ?? "a member"
        do {
            try await convexAPI.leaveRoom(roomId: room.id, userId: userId)
            await sendSystemMessage("\(currentUserName()) removed \(removedName) from the room")
        } catch {
            AlertManager.shared.showAlert(title: "Error", message: friendlyErrorMessage(error))
        }
        isLoading = false
    }

    // MARK: - Private Helpers

    private func currentUserName() -> String {
        userDefaults.string(forKey: "userName") ?? "Someone"
    }

    private func sendSystemMessage(_ content: String) async {
        guard let userId = userDefaults.string(forKey: userIdUserDefaultsKey), !userId.isEmpty else { return }
        do {
            _ = try await convexAPI.sendMessage(
                roomId: room.id,
                userId: userId,
                content: content,
                type: .system,
                senderName: ChatMessage.systemSenderName
            )
        } catch {
            AppLogger.shared.logError("sendSystemMessage", error)
        }
    }
}
