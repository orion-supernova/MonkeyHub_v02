import CloudKit
import SwiftUI
import Combine

@MainActor
class ChatListViewModel: ObservableObject {
    @Published var myRooms: [ChatRoom] = []
    @Published var unreadCounts: [String: Int] = [:]
    
    private let cloudKit = CloudKitManager.shared
    private let userIdUserDefaultsKey = "userId"
    private let userDefaults = UserDefaults.standard
    
    init() {
        setupNotificationObserver()
    }
    
    func loadRooms() async {
        do {
            myRooms = try await cloudKit.fetchChatRooms()
        } catch {
            print("Error loading rooms: \(error)")
        }
    }
    
    func clearUnread(for roomId: String) {
        unreadCounts[roomId] = 0
    }
    
    private func setupNotificationObserver() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("DidReceiveChatMessage"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            let userInfo = notification.userInfo
            let roomId = userInfo?["roomId"] as? String ?? ""
            let messageData = userInfo?["messageData"] as? [String: Any]
            
            let senderId = messageData?[ChatMessage.senderIdKey] as? String ?? ""
            let currentUserId = self.userDefaults.string(forKey: self.userIdUserDefaultsKey) ?? ""
            
            // 1. Update the last message in the room list locally for instant feedback
            if let index = self.myRooms.firstIndex(where: { $0.id == roomId }) {
                let lastMsg = messageData?[ChatMessage.contentKey] as? String ?? "New message"
                
                // Update local room object
                var updatedRoom = self.myRooms[index]
                updatedRoom.lastMessage = lastMsg
                updatedRoom.lastMessageDate = Date() // Use current time for instant update
                
                withAnimation {
                    self.myRooms[index] = updatedRoom
                    
                    // Move the updated room to the top
                    let room = self.myRooms.remove(at: index)
                    self.myRooms.insert(room, at: 0)
                }
                
                // 2. Increment unread count ONLY if:
                // - We are not currently in this room
                // - AND the message is NOT from us (prevents self-badges)
                if NavigationStateManager.shared.currentRoomId != roomId && senderId != currentUserId {
                    self.unreadCounts[roomId, default: 0] += 1
                }
            } else {
                // If it's a new room we're not tracking, fetch all
                Task {
                    await self.loadRooms()
                }
            }
        }
    }
}
