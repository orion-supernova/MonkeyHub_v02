import CloudKit
import SwiftUI

@MainActor
class ChatRoomViewModel: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    private let cloudKit = CloudKitManager.shared
    private let roomId: String

    init(roomId: String) {
        self.roomId = roomId
    }

    func loadMessages() async {
        do {
            messages = try await cloudKit.fetchMessages(for: roomId)
            try await cloudKit.subscribeToMessages(in: roomId)
        } catch {
            print("Error loading messages: \(error)")
        }
    }

    func sendMessage(_ text: String) async {
//        guard let currentUser = cloudKit.currentUser else { return }

        let message = ChatMessage(
            senderId: "currentUser.id",
            senderName: "currentUser.name",
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
//        guard let currentUser = cloudKit.currentUser,
//            let imageData = image.jpegData(compressionQuality: 0.7)
//        else { return }

        do {
            let fileURL = try await cloudKit.uploadAsset(data: /*imageData*/Data(), fileExtension: "jpg")

            let message = ChatMessage(
                senderId: "currentUser.id",
                senderName: "currentUser.name",
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
}
