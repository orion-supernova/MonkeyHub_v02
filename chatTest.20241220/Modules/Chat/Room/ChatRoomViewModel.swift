import CloudKit
import SwiftUI
import Combine

@MainActor
class ChatRoomViewModel: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    
    // Dependencies
    private let repository = ChatRepository.shared
    private let cloudKit = CloudKitManager.shared
    private let userDefaults = UserDefaults.standard
    private let userIdUserDefaultsKey = "userId"
    
    let roomId: String
    private var userId: String = ""
    private var userName: String = "User"
    private var cancellables = Set<AnyCancellable>()

    init(roomId: String) {
        self.roomId = roomId
        print("🎬 ChatRoomViewModel init (\(roomId))")
        
        self.userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
        
        setupBindings()
    }
    
    deinit {
        print("💀 ChatRoomViewModel deinit (\(roomId))")
        // Notify repo that we are leaving
        Task { @MainActor in
            repository.setActiveRoom(nil)
        }
    }
    
    private func setupBindings() {
        // Bind to Repository messages
        repository.$activeRoomMessages
            .receive(on: DispatchQueue.main)
            .assign(to: \.messages, on: self)
            .store(in: &cancellables)
    }

    // Load user data once
    private func loadUserData() async {
        if let user = try? await cloudKit.fetchCurrentUser() {
            self.userName = user.name
        }
    }

    func loadMessages() async {
        await loadUserData()
        // Tell repo we are active in this room
        repository.setActiveRoom(roomId)
        try? await cloudKit.subscribeToMessages(in: roomId)
    }

    func sendMessage(_ text: String) async {
        let message = ChatMessage(
            senderId: userId,
            senderName: userName,
            content: text,
            type: .text,
            roomId: roomId
        )
        await repository.sendMessage(message)
    }
    
    // MARK: - Asset Sending
    // Note: For now, we keep these direct or delegating to CloudKit. 
    // Ideally, Repository would handle asset uploads too, but to keep the refactor focused on text sync first:
    
    func sendImage(_ image: UIImage) async {
        do {
            let fileURL = try await cloudKit.uploadAsset(
                data: image.jpegData(compressionQuality: 0.7) ?? Data(),
                fileExtension: "jpg")

            let message = ChatMessage(
                senderId: userId,
                senderName: userName,
                content: " Photo",
                type: .image,
                roomId: roomId,
                assetURL: fileURL
            )

            await repository.sendMessage(message)
        } catch {
            print("Error sending image: \(error)")
        }
    }

    func sendImage(from url: URL) async {
        do {
            let message = ChatMessage(
                senderId: userId,
                senderName: userName,
                content: " Photo",
                type: .image,
                roomId: roomId,
                assetURL: url
            )

            await repository.sendMessage(message)
        } catch {
            print("Error sending image: \(error)")
        }
    }

    func sendVideo(_ url: URL) async {
        do {
            let message = ChatMessage(
                senderId: userId,
                senderName: userName,
                content: " Video",
                type: .video,
                roomId: roomId,
                assetURL: url
            )

            await repository.sendMessage(message)
        } catch {
            print("Error sending video: \(error)")
        }
    }

    func sendAudio(_ url: URL) async {
        do {
            let message = ChatMessage(
                senderId: userId,
                senderName: userName,
                content: " Voice Message",
                type: .audio,
                roomId: roomId,
                assetURL: url
            )

            await repository.sendMessage(message)
        } catch {
            print("Error sending audio: \(error)")
        }
    }

    func deleteMessage(_ messageId: String) async {
        await repository.deleteMessage(messageId, in: roomId)
    }
}
