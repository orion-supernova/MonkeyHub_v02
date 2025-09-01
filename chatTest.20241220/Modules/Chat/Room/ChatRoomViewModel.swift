import CloudKit
import SwiftUI

@MainActor
class ChatRoomViewModel: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    private let cloudKit = CloudKitManager.shared
    private let roomId: String
    private let userDefaults = UserDefaults.standard
    private let userIdUserDefaultsKey = "userId"

    // Store user data
    private var userId: String = ""
    private var userName: String = "User"

    init(roomId: String) {
        self.roomId = roomId
        // Load user ID from UserDefaults
        self.userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
    }

    // Load user data once
    private func loadUserData() async {
        if let user = try? await cloudKit.fetchCurrentUser() {
            self.userName = user.name
        }
    }

    func loadMessages() async {
        do {
            // Load user data first
            await loadUserData()

            messages = try await cloudKit.fetchMessages(for: roomId)
            try await cloudKit.subscribeToMessages(in: roomId)
        } catch {
            print("Error loading messages: \(error)")
        }
    }

    func sendMessage(_ text: String) async {
        let message = ChatMessage(
            senderId: userId,
            senderName: userName,
            content: text,
            type: .text,
            roomId: roomId
        )

        do {
            try await cloudKit.sendMessage(message)
            messages.insert(message, at: 0)
        } catch {
            print("Error sending message: \(error)")
        }
    }

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

            try await cloudKit.sendMessage(message)
            messages.insert(message, at: 0)
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

            try await cloudKit.sendMessage(message)
            messages.insert(message, at: 0)
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

            try await cloudKit.sendMessage(message)
            messages.insert(message, at: 0)
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

            try await cloudKit.sendMessage(message)
            messages.insert(message, at: 0)
        } catch {
            print("Error sending audio: \(error)")
        }
    }
}
