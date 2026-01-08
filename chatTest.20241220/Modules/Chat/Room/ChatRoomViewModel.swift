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
        
        setupNotificationObserver()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupNotificationObserver() {
        print("👀 ChatRoomViewModel (\(roomId)) setting up notification observer")
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("DidReceiveChatMessage"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            let userInfo = notification.userInfo
            let incomingRoomId = userInfo?["roomId"] as? String ?? "nil"
            
            print("📬 ChatRoomViewModel (\(self.roomId)) received notification for room: \(incomingRoomId)")
            
            guard incomingRoomId == self.roomId else {
                print("⏭️ ChatRoomViewModel (\(self.roomId)) ignoring notification for different room")
                return
            }
            
            // Try to update instantly from payload data
            if let messageData = userInfo?["messageData"] as? [String: Any] {
                self.handleIncomingMessageData(messageData)
            } else {
                // Fallback to fetch if no data in payload
                Task {
                    print("🔄 ChatRoomViewModel (\(self.roomId)) starting fallback refresh...")
                    await self.refreshMessages()
                }
            }
        }
    }
    
    private func handleIncomingMessageData(_ data: [String: Any]) {
        guard let roomId = data[ChatMessage.roomIdKey] as? String,
              let content = data[ChatMessage.contentKey] as? String,
              let senderId = data[ChatMessage.senderIdKey] as? String,
              let senderName = data[ChatMessage.senderNameKey] as? String,
              let typeRaw = data[ChatMessage.typeKey] as? String,
              let type = MessageType(rawValue: typeRaw),
              let recordID = data["recordID"] as? String else {
            print("⚠️ Incomplete message data in payload")
            return
        }
        
        // Double check it's for this room
        guard roomId == self.roomId else { return }
        
        // Use provided timestamp or fallback to now
        let timestamp = data[ChatMessage.timestampKey] as? Date ?? Date()
        
        // Check if message already exists (using recordID as the primary key here)
        if messages.contains(where: { $0.id == recordID || $0.content == content && abs($0.timestamp.timeIntervalSince(timestamp)) < 1 }) {
            print("ℹ️ Message already in list, skipping instant insert")
            return
        }
        
        let message = ChatMessage(
            id: recordID,
            senderId: senderId,
            senderName: senderName,
            content: content,
            type: type,
            timestamp: timestamp,
            roomId: roomId
        )
        
        print("✨ Inserting message instantly: \(message.content.prefix(20))")
        withAnimation {
            messages.insert(message, at: 0)
        }
    }
    
    private func refreshMessages() async {
        do {
            let latestMessages = try await cloudKit.fetchMessages(for: roomId)
            print("📈 ChatRoomViewModel (\(roomId)) fetched \(latestMessages.count) messages")
            
            // Log the first few message IDs to see if they are new
            for (index, msg) in latestMessages.prefix(3).enumerated() {
                print("   [\(index)] Msg: \(msg.content.prefix(20))... (ID: \(msg.id))")
            }
            
            self.messages = latestMessages
            print("✅ ChatRoomViewModel (\(roomId)) messages updated")
        } catch {
            print("❌ ChatRoomViewModel (\(roomId)) error refreshing: \(error)")
        }
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
            try? await cloudKit.subscribeToMessages(in: roomId)
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

    func deleteMessage(_ messageId: String) async {
        do {
            try await cloudKit.deleteChatMessage(messageId)
            await MainActor.run {
                withAnimation {
                    messages.removeAll(where: { $0.id == messageId })
                }
            }
        } catch {
            print("Error deleting message: \(error)")
        }
    }
}
